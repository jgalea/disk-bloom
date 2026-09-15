import Foundation

/// Why free space does not move by as much as you just deleted.
///
/// Time Machine keeps local APFS snapshots on the boot volume, and a snapshot
/// pins the blocks of every file it captured. Delete 11 GB and `df` can report
/// the same free space afterwards, because the blocks belong to a snapshot
/// until it expires. The space is not lost, and it is not leaked; it is held.
public struct VolumeInsight: Sendable, Equatable {
    /// Bytes macOS will hand back automatically when a volume runs low.
    public let purgeableBytes: Int64
    /// Local Time Machine snapshots pinning blocks on this volume.
    public let localSnapshots: [String]

    public var snapshotCount: Int { localSnapshots.count }

    public var holdsSpaceBack: Bool { snapshotCount > 0 || purgeableBytes > 0 }

    public init(purgeableBytes: Int64, localSnapshots: [String]) {
        self.purgeableBytes = purgeableBytes
        self.localSnapshots = localSnapshots
    }

    /// One sentence for the UI, or nil when nothing is being held back.
    public var explanation: String? {
        guard holdsSpaceBack else { return nil }
        var parts: [String] = []
        if snapshotCount > 0 {
            let noun = snapshotCount == 1 ? "snapshot is" : "snapshots are"
            parts.append("\(snapshotCount) local Time Machine \(noun) pinning blocks from deleted files")
        }
        if purgeableBytes > 0 {
            parts.append("\(formatted(purgeableBytes)) is purgeable and comes back automatically under disk pressure")
        }
        return parts.joined(separator: ", and ") + "."
    }

    private func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func measure(volume: URL = URL(fileURLWithPath: "/")) -> VolumeInsight {
        VolumeInsight(
            purgeableBytes: purgeable(volume: volume),
            localSnapshots: snapshots(volume: volume)
        )
    }

    private static func purgeable(volume: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let important = values.volumeAvailableCapacityForImportantUsage,
              let free = values.volumeAvailableCapacity
        else { return 0 }
        // "Important usage" includes space macOS would purge to make room;
        // the difference over plain free space is what is currently held.
        return max(0, Int64(important) - Int64(free))
    }

    private static func snapshots(volume: URL) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", volume.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
    }
}
