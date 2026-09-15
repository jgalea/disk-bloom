import XCTest
@testable import BloomCore

/// StaleFinder is unit-tested against hand-built trees; this covers the seam
/// where a real scan feeds it, which is where the mtime has to survive.
final class StaleIntegrationTests: XCTestCase {
    var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-staleint-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.appendingPathComponent("old-archive"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("active"), withIntermediateDirectories: true)
        try Data(count: 150 << 20).write(to: fixture.appendingPathComponent("old-archive/backup.img"))
        try Data(count: 120 << 20).write(to: fixture.appendingPathComponent("active/current.img"))

        let old = Date(timeIntervalSinceNow: -580 * 24 * 60 * 60)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: fixture.appendingPathComponent("old-archive/backup.img").path)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: fixture.appendingPathComponent("old-archive").path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    func testAScannedColdFolderIsFound() async throws {
        let root = await DiskScanner.scan(url: fixture, progress: ScanProgress())

        let archive = try XCTUnwrap(root.children.first { $0.name == "old-archive" })
        XCTAssertGreaterThan(archive.size, 100 << 20, "fixture must clear the size floor")
        XCTAssertGreaterThan(archive.modified, 0, "scanner must carry the mtime through")

        let stale = StaleFinder.stale(tree: root)
        XCTAssertEqual(stale.map(\.name), ["old-archive"])
    }
}
