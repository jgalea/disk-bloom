import Foundation

/// Large things nothing has touched in a long time.
///
/// Size alone cannot tell you what to delete, because the biggest folder on a
/// disk is usually the one being used most. Size crossed with age can: an
/// 11 GB file last written four months ago is a different proposition from an
/// 11 GB file written this morning.
public enum StaleFinder {
    public static let defaultAge: TimeInterval = 90 * 24 * 60 * 60

    /// Nodes at least `minimumBytes` whose entire subtree has gone untouched
    /// for `olderThan`, largest first.
    ///
    /// Only the outermost cold node in any branch is reported: if a whole
    /// folder is cold then so is everything in it, and listing all of it is
    /// noise. Nodes with an unknown mtime are never reported, since unknown
    /// is not evidence of age.
    public static func stale(
        tree: FileNode,
        olderThan: TimeInterval = defaultAge,
        minimumBytes: Int64 = 100 << 20,
        now: Date = Date()
    ) -> [FileNode] {
        var found: [FileNode] = []
        var stack = [tree]
        while let node = stack.popLast() {
            guard node.size >= minimumBytes else { continue }
            if let age = node.age(now: now), age >= olderThan, node !== tree {
                found.append(node)
                continue
            }
            stack.append(contentsOf: node.children)
        }
        return found.sorted { $0.size > $1.size }
    }
}
