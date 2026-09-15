import XCTest
@testable import BloomCore

final class ExclusionsTests: XCTestCase {
    var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-exclude-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.appendingPathComponent("keep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("mirror/deep"), withIntermediateDirectories: true)
        try Data(count: 20_000).write(to: fixture.appendingPathComponent("keep/small.bin"))
        try Data(count: 2_000_000).write(to: fixture.appendingPathComponent("mirror/deep/huge.bin"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    func testExcludedSubtreeIsNeitherCountedNorShown() async throws {
        let excluded = Exclusions(paths: [fixture.appendingPathComponent("mirror").path])
        let progress = ScanProgress()
        let root = await DiskScanner.scan(url: fixture, progress: progress, exclusions: excluded)

        XCTAssertNil(root.children.first { $0.name == "mirror" })
        XCTAssertEqual(progress.snapshot.excluded, 1)
        // The 2 MB behind the exclusion must not reach any ancestor's total.
        XCTAssertLessThan(root.size, 1_000_000)
    }

    func testWithoutExclusionsTheSubtreeIsCounted() async throws {
        let root = await DiskScanner.scan(url: fixture, progress: ScanProgress())
        XCTAssertNotNil(root.children.first { $0.name == "mirror" })
        XCTAssertGreaterThan(root.size, 2_000_000)
    }

    func testDescendantsOfAnExcludedPathAreExcluded() {
        let exclusions = Exclusions(paths: ["/srv/data/caches"])
        XCTAssertTrue(exclusions.excludes("/srv/data/caches"))
        XCTAssertTrue(exclusions.excludes("/srv/data/caches/com.example.app"))
        // A sibling sharing the prefix is a different directory, not a child.
        XCTAssertFalse(exclusions.excludes("/srv/data/cachesOther"))
        XCTAssertFalse(exclusions.excludes("/srv/data"))
    }

    func testNormalizationRejectsUnusableEntries() {
        XCTAssertNil(Exclusions.normalize(""))
        XCTAssertNil(Exclusions.normalize("   "))
        XCTAssertNil(Exclusions.normalize("relative/path"))
        // Excluding the root would make every scan empty.
        XCTAssertNil(Exclusions.normalize("/"))
        XCTAssertEqual(Exclusions.normalize("/tmp/foo/"), "/tmp/foo")
    }

    func testTildeExpands() throws {
        let home = NSHomeDirectory()
        XCTAssertEqual(Exclusions.normalize("~/Library"), home + "/Library")
        XCTAssertTrue(Exclusions(paths: ["~/Library"]).excludes(home + "/Library/Caches"))
    }

    func testEmptyExclusionsExcludeNothing() {
        XCTAssertTrue(Exclusions.none.isEmpty)
        XCTAssertFalse(Exclusions.none.excludes("/anything/at/all"))
    }
}
