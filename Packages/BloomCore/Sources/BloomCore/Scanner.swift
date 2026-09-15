import Foundation
import os

public struct ScanSnapshot: Sendable {
    public var items: Int
    public var bytes: Int64
    public var skipped: Int
    public var excluded: Int

    public init(items: Int = 0, bytes: Int64 = 0, skipped: Int = 0, excluded: Int = 0) {
        self.items = items
        self.bytes = bytes
        self.skipped = skipped
        self.excluded = excluded
    }
}

/// Thread-safe progress counters the UI polls while a scan runs.
public final class ScanProgress: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: ScanSnapshot(items: 0, bytes: 0, skipped: 0))

    public init() {}

    func add(items: Int, bytes: Int64) {
        state.withLock {
            $0.items += items
            $0.bytes += bytes
        }
    }

    func addSkipped() {
        state.withLock { $0.skipped += 1 }
    }

    func addExcluded() {
        state.withLock { $0.excluded += 1 }
    }

    public var snapshot: ScanSnapshot {
        state.withLock { $0 }
    }
}

struct DevIno: Hashable, Sendable {
    let dev: UInt64
    let ino: UInt64
}

/// Inodes already counted in this scan, keyed by (device, inode).
/// Directories: APFS firmlinks expose the same directory under two paths
/// (/Applications and /System/Volumes/Data/Applications), which double-counts
/// everything on a whole-disk scan; claiming also guards against cycles.
/// Files: only hardlinked ones (nlink > 1) are claimed, so rsync --link-dest
/// snapshot farms count each file once (du semantics), not once per link.
final class VisitedInodes: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: Set<DevIno>())

    /// Returns true the first time an identity is claimed, false after.
    func claim(_ identity: DevIno) -> Bool {
        state.withLock { $0.insert(identity).inserted }
    }
}

/// Counting semaphore deciding whether a subdirectory scan may run as its own
/// concurrent task. Fat directories grab slots and fan out; once slots are
/// taken, recursion continues inline in the current task.
private final class ParallelBudget: Sendable {
    private let slots: OSAllocatedUnfairLock<Int>

    init(limit: Int) {
        slots = OSAllocatedUnfairLock(initialState: limit)
    }

    func tryAcquire() -> Bool {
        slots.withLock {
            if $0 > 0 { $0 -= 1; return true }
            return false
        }
    }

    func release() {
        slots.withLock { $0 += 1 }
    }
}

public enum DiskScanner {
    // vnode object types as returned in ATTR_CMN_OBJTYPE (sys/vnode.h vtype).
    private static let VREG: UInt32 = 1
    private static let VDIR: UInt32 = 2

    /// Scan a directory tree. Never follows symlinks, never crosses volume
    /// boundaries, counts hardlinked files once, visits each directory inode
    /// once. Unreadable directories are counted in `progress.skipped`.
    ///
    /// Enumeration uses getattrlistbulk: one syscall returns a batch of
    /// entries with name, type, inode, link count, and allocated size —
    /// several times faster on a cold cache than readdir + per-entry stat.
    public static func scan(url: URL, progress: ScanProgress, exclusions: Exclusions = .none) async -> FileNode {
        let path = (url.path as NSString).standardizingPath
        let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent

        // Concurrent tasks each hold an open fd per directory on their
        // recursion path; the default soft limit (256) is too small.
        var limits = rlimit()
        if getrlimit(RLIMIT_NOFILE, &limits) == 0, limits.rlim_cur < 8192 {
            limits.rlim_cur = min(8192, limits.rlim_max)
            setrlimit(RLIMIT_NOFILE, &limits)
        }

        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else {
            progress.addSkipped()
            return FileNode(name: name, isDirectory: true, size: 0, rootPath: path)
        }
        var st = stat()
        var rootDevice: UInt64?
        var rootModified: Int64 = 0
        let visited = VisitedInodes()
        if fstat(fd, &st) == 0 {
            let devino = DevIno(dev: UInt64(bitPattern: Int64(st.st_dev)), ino: st.st_ino)
            rootDevice = devino.dev
            rootModified = Int64(st.st_mtimespec.tv_sec)
            _ = visited.claim(devino)
        }
        let budget = ParallelBudget(limit: max(4, ProcessInfo.processInfo.activeProcessorCount * 2))

        let node = await scanDirectory(
            fd: fd, name: name, path: path, ownModified: rootModified,
            rootDevice: rootDevice, visited: visited, progress: progress,
            budget: budget, exclusions: exclusions
        )
        // Rebuild the root so it carries its absolute path for the UI.
        return FileNode(
            name: name, isDirectory: true, size: 0, modified: node.modified,
            children: node.children, rootPath: path
        )
    }

    /// Takes ownership of `fd` and closes it before returning.
    private static func scanDirectory(
        fd: Int32, name: String, path: String, ownModified: Int64, rootDevice: UInt64?,
        visited: VisitedInodes, progress: ScanProgress, budget: ParallelBudget,
        exclusions: Exclusions
    ) async -> FileNode {
        var leaves: [FileNode] = []
        var subdirs: [(name: String, modified: Int64)] = []
        var localBytes: Int64 = 0

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = ATTR_CMN_RETURNED_ATTRS | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
        attrs.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE)

        let bufferSize = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        enumerate: while true {
            let count = getattrlistbulk(fd, &attrs, buffer, bufferSize, 0)
            if count <= 0 { break }

            var cursor = buffer
            for _ in 0..<count {
                let entry = cursor
                let entryLength = Int(entry.load(as: UInt32.self))
                defer { cursor = entry + entryLength }
                guard entryLength > 0 else { break enumerate } // malformed; bail out

                var field = entry + MemoryLayout<UInt32>.size
                let returned = field.load(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size

                var entryName = ""
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = field.load(as: attrreference.self)
                    entryName = String(cString: (field + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    field += MemoryLayout<attrreference>.size
                }
                var objType: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    objType = field.load(as: UInt32.self)
                    field += MemoryLayout<UInt32>.size
                }
                // Attributes arrive in bitmap order, so MODTIME (0x400) is
                // unpacked after OBJTYPE (0x08) and before FILEID (0x2000000).
                var modified: Int64 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    modified = Int64(field.loadUnaligned(as: timespec.self).tv_sec)
                    field += MemoryLayout<timespec>.size
                }
                var fileID: UInt64 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self)
                    field += MemoryLayout<UInt64>.size
                }
                var linkCount: UInt32 = 1
                if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                    linkCount = field.load(as: UInt32.self)
                    field += MemoryLayout<UInt32>.size
                }
                var allocated: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocated = field.loadUnaligned(as: Int64.self)
                }
                guard !entryName.isEmpty else { continue }

                if objType == VDIR {
                    subdirs.append((entryName, modified))
                } else {
                    if objType == VREG, linkCount > 1, let rootDevice {
                        // Hardlink: count the first sighting only (du semantics).
                        if !visited.claim(DevIno(dev: rootDevice, ino: fileID)) { continue }
                    }
                    localBytes += allocated
                    leaves.append(FileNode(
                        name: entryName, isDirectory: false, size: allocated, modified: modified
                    ))
                }
            }
        }
        progress.add(items: leaves.count + 1, bytes: localBytes)

        if subdirs.isEmpty {
            close(fd)
            return FileNode(name: name, isDirectory: true, size: 0, modified: ownModified, children: leaves)
        }

        // Open + identity-check each subdirectory relative to this fd.
        // openat crosses mount points, so the device check happens on the
        // opened fd; firmlink/cycle duplicates lose the visited claim.
        func openSubdirectory(_ sub: String) -> Int32? {
            let childFD = openat(fd, sub, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard childFD >= 0 else {
                progress.addSkipped()
                return nil
            }
            var st = stat()
            guard fstat(childFD, &st) == 0 else { close(childFD); return nil }
            let devino = DevIno(dev: UInt64(bitPattern: Int64(st.st_dev)), ino: st.st_ino)
            guard rootDevice == nil || devino.dev == rootDevice, visited.claim(devino) else {
                close(childFD)
                return nil
            }
            return childFD
        }

        // Subdirectories run concurrently while budget slots last; the rest
        // recurse inline in this task. Fat directories parallelize, deep
        // chains stay cheap. Skipped/duplicate dirs still appear as empty
        // nodes so permission problems are visible in the UI.
        var children = leaves
        var spawn: [(name: String, fd: Int32, path: String, modified: Int64)] = []
        var inline: [(name: String, fd: Int32, path: String, modified: Int64)] = []
        for sub in subdirs {
            let childPath = path == "/" ? "/" + sub.name : path + "/" + sub.name
            // Excluded trees are not opened, not counted, and not shown.
            if exclusions.excludes(childPath) {
                progress.addExcluded()
                continue
            }
            guard let childFD = openSubdirectory(sub.name) else {
                children.append(FileNode(name: sub.name, isDirectory: true, size: 0, modified: sub.modified))
                continue
            }
            let entry = (name: sub.name, fd: childFD, path: childPath, modified: sub.modified)
            if budget.tryAcquire() { spawn.append(entry) } else { inline.append(entry) }
        }
        close(fd)

        let spawned = await withTaskGroup(of: FileNode.self) { group in
            for entry in spawn {
                group.addTask {
                    let node = await scanDirectory(
                        fd: entry.fd, name: entry.name, path: entry.path, ownModified: entry.modified,
                        rootDevice: rootDevice, visited: visited, progress: progress,
                        budget: budget, exclusions: exclusions
                    )
                    budget.release()
                    return node
                }
            }
            // Inline recursion overlaps with the spawned tasks.
            var result: [FileNode] = []
            for entry in inline {
                result.append(await scanDirectory(
                    fd: entry.fd, name: entry.name, path: entry.path, ownModified: entry.modified,
                    rootDevice: rootDevice, visited: visited, progress: progress,
                    budget: budget, exclusions: exclusions
                ))
            }
            for await node in group { result.append(node) }
            return result
        }
        children.append(contentsOf: spawned)
        return FileNode(name: name, isDirectory: true, size: 0, modified: ownModified, children: children)
    }

    struct Identity {
        let id: DevIno
        var dev: UInt64 { id.dev }
    }

    static func identity(of path: String) -> Identity? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        // st_dev is a signed Int32 and IS negative for synthetic filesystems
        // (devfs reports e.g. -1465048812). A plain UInt64(_:) conversion
        // traps; only equality matters here, so preserve the bit pattern.
        return Identity(id: DevIno(dev: UInt64(bitPattern: Int64(st.st_dev)), ino: st.st_ino))
    }
}
