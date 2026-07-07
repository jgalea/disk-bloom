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
    public private(set) var children: [FileNode]
    public private(set) weak var parent: FileNode?
    private let rootPath: String?

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public init(
        name: String, isDirectory: Bool, size: Int64,
        children: [FileNode] = [], rootPath: String? = nil
    ) {
        self.name = name
        self.rootPath = rootPath
        self.isDirectory = isDirectory
        self.children = children.sorted { $0.size > $1.size }
        self.size = isDirectory ? children.reduce(0) { $0 + $1.size } + size : size
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
