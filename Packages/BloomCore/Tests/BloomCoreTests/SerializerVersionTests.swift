import XCTest
@testable import BloomCore

final class SerializerVersionTests: XCTestCase {
    var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-blm-\(UUID().uuidString).blm")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testRoundTripPreservesModificationTimes() throws {
        let tree = FileNode(
            name: "root", isDirectory: true, size: 0, modified: 1_500_000_000,
            children: [
                FileNode(name: "old.bin", isDirectory: false, size: 1024, modified: 1_400_000_000),
                FileNode(name: "new.bin", isDirectory: false, size: 2048, modified: 1_700_000_000),
            ],
            rootPath: "/tmp/root"
        )

        try TreeSerializer.write(root: tree, skipped: 3, to: url)
        let (restored, skipped) = try TreeSerializer.read(from: url)

        XCTAssertEqual(skipped, 3)
        let old = try XCTUnwrap(restored.children.first { $0.name == "old.bin" })
        let new = try XCTUnwrap(restored.children.first { $0.name == "new.bin" })
        XCTAssertEqual(old.modified, 1_400_000_000)
        XCTAssertEqual(new.modified, 1_700_000_000)
        // The directory still reports its newest descendant after a round trip.
        XCTAssertEqual(restored.modified, 1_700_000_000)
    }

    func testLegacyBLM1SnapshotsStillRead() throws {
        var data = Data("BLM1".utf8)
        func appendU16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendU32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendU64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendName(_ s: String) {
            let bytes = Array(s.utf8)
            appendU16(UInt16(bytes.count))
            data.append(contentsOf: bytes)
        }

        let rootPath = Array("/tmp/legacy".utf8)
        appendU32(UInt32(rootPath.count))
        data.append(contentsOf: rootPath)
        appendU32(7) // skipped

        data.append(1) // root is a directory
        appendName("legacy")
        appendU32(1)   // one child

        data.append(0) // the child is a file
        appendName("blob.bin")
        appendU64(4096)

        try data.write(to: url)

        let (root, skipped) = try TreeSerializer.read(from: url)
        XCTAssertEqual(skipped, 7)
        XCTAssertEqual(root.path, "/tmp/legacy")
        let child = try XCTUnwrap(root.children.first)
        XCTAssertEqual(child.name, "blob.bin")
        XCTAssertEqual(child.size, 4096)
        // BLM1 carried no timestamps, so they read back as unknown, not as 1970.
        XCTAssertEqual(child.modified, 0)
        XCTAssertNil(child.age())
    }

    func testUnknownMagicIsRejected() throws {
        try Data("BLM9....................".utf8).write(to: url)
        XCTAssertThrowsError(try TreeSerializer.read(from: url)) { error in
            XCTAssertEqual(error as? TreeSerializer.SerializerError, .unsupportedVersion)
        }
    }
}
