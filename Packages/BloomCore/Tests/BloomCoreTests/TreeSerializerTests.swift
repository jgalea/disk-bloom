import XCTest
@testable import BloomCore

final class TreeSerializerTests: XCTestCase {
    func testRoundTripPreservesStructureSizesAndPath() throws {
        func file(_ name: String, _ size: Int64) -> FileNode {
            FileNode(name: name, isDirectory: false, size: size)
        }
        let tree = FileNode(
            name: "root", isDirectory: true, size: 0,
            children: [
                FileNode(name: "a", isDirectory: true, size: 0, children: [
                    file("big.bin", 5_000_000),
                    FileNode(name: "empty", isDirectory: true, size: 0),
                    file("café ☕️.txt", 42),
                ]),
                file("loose", 1234),
            ],
            rootPath: "/tmp/serializer-фикстура"
        )

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-tree-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: out) }

        try TreeSerializer.write(root: tree, skipped: 7, to: out)
        let (loaded, skipped) = try TreeSerializer.read(from: out)

        XCTAssertEqual(skipped, 7)
        XCTAssertEqual(loaded.path, "/tmp/serializer-фикстура")
        XCTAssertEqual(loaded.size, tree.size)
        XCTAssertEqual(loaded.children.count, 2)

        let a = try XCTUnwrap(loaded.children.first { $0.name == "a" })
        XCTAssertEqual(a.size, 5_000_042)
        XCTAssertEqual(a.children.map(\.name), ["big.bin", "café ☕️.txt", "empty"])
        XCTAssertEqual(a.children[0].size, 5_000_000)
        XCTAssertTrue(a.children[2].isDirectory)

        // Paths reassemble through the parent chain after deserialization.
        XCTAssertEqual(a.children[0].path, "/tmp/serializer-фикстура/a/big.bin")
    }

    func testTruncatedDataThrowsInsteadOfCrashing() throws {
        let tree = FileNode(
            name: "r", isDirectory: true, size: 0,
            children: [FileNode(name: "f", isDirectory: false, size: 9)],
            rootPath: "/x"
        )
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-trunc-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: out) }
        try TreeSerializer.write(root: tree, skipped: 0, to: out)

        let full = try Data(contentsOf: out)
        try full.prefix(full.count - 5).write(to: out)
        XCTAssertThrowsError(try TreeSerializer.read(from: out))
    }
}
