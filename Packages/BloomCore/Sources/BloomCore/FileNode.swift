import Foundation

/// Immutable-after-construction tree node. Built off the main actor by the
/// scanner, then handed to the UI and never mutated except by `detach()`
/// (trash flow), which the app performs on the main actor.
///
/// Nodes store only their name; the absolute path is reassembled from the
/// parent chain (the root keeps its full path), which keeps multi-million
/// node trees compact.
public final class FileNode: @unchecked Sendable, Identifiable {
    public let name: String
    public let isDirectory: Bool
    public private(set) var size: Int64
    /// Last-modified time, Unix epoch seconds. 0 means unknown.
    ///
    /// A directory reports the newest mtime in its subtree, including its own:
    /// adding or removing an entry bumps a directory's mtime, and that counts
    /// as the tree having been touched. Erring that way keeps live data from
    /// ever being labelled stale, at the cost of missing some genuinely cold
    /// trees. Scanning does not update this.
    public let modified: Int64
    public private(set) var children: [FileNode]
    public private(set) weak var parent: FileNode?
    private let rootPath: String?

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public init(
        name: String, isDirectory: Bool, size: Int64, modified: Int64 = 0,
        children: [FileNode] = [], rootPath: String? = nil
    ) {
        self.name = name
        self.rootPath = rootPath
        self.isDirectory = isDirectory
        self.children = children.sorted { $0.size > $1.size }
        self.size = isDirectory ? children.reduce(0) { $0 + $1.size } + size : size
        if isDirectory {
            self.modified = children.reduce(modified) { Swift.max($0, $1.modified) }
        } else {
            self.modified = modified
        }
        for child in self.children { child.parent = self }
    }

    public var path: String {
        if let rootPath { return rootPath }
        guard let parent else { return "/" + name }
        let parentPath = parent.path
        return parentPath == "/" ? "/" + name : parentPath + "/" + name
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var ancestors: [FileNode] {
        var result: [FileNode] = []
        var node = parent
        while let n = node {
            result.append(n)
            node = n.parent
        }
        return result.reversed()
    }

    /// Seconds since this node's subtree was last touched, or nil when the
    /// mtime is unknown (old snapshot formats, or an attribute the volume
    /// declined to return).
    public func age(now: Date = Date()) -> TimeInterval? {
        guard modified > 0 else { return nil }
        return Swift.max(0, now.timeIntervalSince1970 - TimeInterval(modified))
    }

    /// Remove this node from its parent and subtract its size up the chain.
    /// Call on the main actor after a successful move to Trash.
    public func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var node: FileNode? = parent
        while let n = node {
            n.size -= size
            node = n.parent
        }
        self.parent = nil
    }
}
