import Foundation

/// Compact binary format for shipping a scanned tree between the privileged
/// helper and the app. Preorder walk; little-endian.
///
/// Header: "BLM1" + u32 rootPathLength + rootPath + u32 skipped
/// Node:   u8 isDirectory + u16 nameLength + name(UTF-8)
///         + (file: s64 size) | (directory: u32 childCount, then children)
public enum TreeSerializer {
    public enum SerializerError: Error {
        case malformed
        case unsupportedVersion
    }

    private static let magic = Array("BLM1".utf8)

    public static func write(root: FileNode, skipped: Int, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try write(root: root, skipped: skipped, to: handle)
    }

    /// Stream the tree into an already-open handle (e.g. a descriptor passed
    /// over XPC from the app to the privileged helper).
    public static func write(root: FileNode, skipped: Int, to handle: FileHandle) throws {
        var buffer = Data(capacity: 4 << 20)
        buffer.append(contentsOf: magic)
        appendString32(root.path, to: &buffer)
        appendInteger(UInt32(clamping: skipped), to: &buffer)

        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            buffer.append(node.isDirectory ? 1 : 0)
            appendString16(node.name, to: &buffer)
            if node.isDirectory {
                appendInteger(UInt32(node.children.count), to: &buffer)
                stack.append(contentsOf: node.children.reversed())
            } else {
                appendInteger(UInt64(bitPattern: node.size), to: &buffer)
            }
            if buffer.count > (4 << 20) - 4096 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        try handle.write(contentsOf: buffer)
    }

    public static func read(from url: URL) throws -> (root: FileNode, skipped: Int) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var offset = 0

        guard data.count > magic.count + 8, Array(data.prefix(magic.count)) == magic else {
            throw SerializerError.unsupportedVersion
        }
        offset = magic.count
        let rootPath = try readString(data, &offset, lengthBytes: 4)
        let skipped = Int(try readInteger(data, &offset, as: UInt32.self))

        let root = try readNode(data, &offset, rootPath: rootPath)
        guard root.isDirectory else { throw SerializerError.malformed }
        return (root, skipped)
    }

    // MARK: - Node reading (explicit stack; tree depth is filesystem depth)

    private static func readNode(_ data: Data, _ offset: inout Int, rootPath: String?) throws -> FileNode {
        let isDirectory = try readInteger(data, &offset, as: UInt8.self) == 1
        let name = try readString(data, &offset, lengthBytes: 2)
        if !isDirectory {
            let size = Int64(bitPattern: try readInteger(data, &offset, as: UInt64.self))
            return FileNode(name: name, isDirectory: false, size: size)
        }
        let childCount = Int(try readInteger(data, &offset, as: UInt32.self))
        var children: [FileNode] = []
        children.reserveCapacity(childCount)
        for _ in 0..<childCount {
            children.append(try readNode(data, &offset, rootPath: nil))
        }
        return FileNode(name: name, isDirectory: true, size: 0, children: children, rootPath: rootPath)
    }

    // MARK: - Primitives

    private static func appendInteger<T: FixedWidthInteger>(_ value: T, to buffer: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
    }

    private static func appendString16(_ string: String, to buffer: inout Data) {
        let bytes = Array(string.utf8).prefix(Int(UInt16.max))
        appendInteger(UInt16(bytes.count), to: &buffer)
        buffer.append(contentsOf: bytes)
    }

    private static func appendString32(_ string: String, to buffer: inout Data) {
        let bytes = Array(string.utf8)
        appendInteger(UInt32(bytes.count), to: &buffer)
        buffer.append(contentsOf: bytes)
    }

    private static func readInteger<T: FixedWidthInteger>(_ data: Data, _ offset: inout Int, as type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { throw SerializerError.malformed }
        var value = T.zero
        withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: (data.startIndex + offset)..<(data.startIndex + offset + size))
        }
        offset += size
        return T(littleEndian: value)
    }

    private static func readString(_ data: Data, _ offset: inout Int, lengthBytes: Int) throws -> String {
        let length: Int
        if lengthBytes == 2 {
            length = Int(try readInteger(data, &offset, as: UInt16.self))
        } else {
            length = Int(try readInteger(data, &offset, as: UInt32.self))
        }
        guard offset + length <= data.count else { throw SerializerError.malformed }
        let range = (data.startIndex + offset)..<(data.startIndex + offset + length)
        offset += length
        return String(decoding: data[range], as: UTF8.self)
    }
}
