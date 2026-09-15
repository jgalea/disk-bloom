import XCTest
@testable import BloomCore

final class ModifiedTimeTests: XCTestCase {
    var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-mtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: fixture.appendingPathComponent("stale"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixture.appendingPathComponent("fresh"), withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    private func write(_ relative: String, bytes: Int, modified: Date) throws {
        let url = fixture.appendingPathComponent(relative)
        try Data(count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    /// Writing into a directory bumps that directory's own mtime, so an aged
    /// fixture has to age the directory afterwards, exactly as a real
    /// long-untouched folder is aged by nothing having written to it.
    private func age(_ relative: String, to modified: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: modified],
            ofItemAtPath: fixture.appendingPathComponent(relative).path
        )
    }

    func testScannerCapturesModificationTime() async throws {
        let old = Date(timeIntervalSince1970: 1_500_000_000)
        try write("stale/old.bin", bytes: 4096, modified: old)

        let root = await DiskScanner.scan(url: fixture, progress: ScanProgress())
        let stale = try XCTUnwrap(root.children.first { $0.name == "stale" })
        let file = try XCTUnwrap(stale.children.first { $0.name == "old.bin" })

        XCTAssertEqual(file.modified, Int64(old.timeIntervalSince1970))
    }

    func testDirectoryReportsNewestModificationInSubtree() async throws {
        let old = Date(timeIntervalSince1970: 1_500_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        try write("stale/old.bin", bytes: 4096, modified: old)
        try write("fresh/recent.bin", bytes: 4096, modified: newer)
        try age("stale", to: old)

        let root = await DiskScanner.scan(url: fixture, progress: ScanProgress())
        let stale = try XCTUnwrap(root.children.first { $0.name == "stale" })

        // A directory is only as stale as its freshest descendant.
        XCTAssertEqual(stale.modified, Int64(old.timeIntervalSince1970))
        XCTAssertGreaterThanOrEqual(root.modified, Int64(newer.timeIntervalSince1970))
    }

    func testAgeIsNilWhenModificationTimeIsUnknown() {
        let unknown = FileNode(name: "x", isDirectory: false, size: 10)
        XCTAssertNil(unknown.age())

        let known = FileNode(name: "y", isDirectory: false, size: 10, modified: 1_500_000_000)
        let age = try? XCTUnwrap(known.age(now: Date(timeIntervalSince1970: 1_500_086_400)))
        XCTAssertEqual(age ?? 0, 86_400, accuracy: 1)
    }

    func testAgeNeverGoesNegativeForFutureTimestamps() {
        let future = FileNode(name: "z", isDirectory: false, size: 10, modified: 2_000_000_000)
        XCTAssertEqual(future.age(now: Date(timeIntervalSince1970: 1_500_000_000)), 0)
    }
}
