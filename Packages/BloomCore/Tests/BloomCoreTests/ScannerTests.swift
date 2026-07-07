import XCTest
@testable import BloomCore

final class ScannerTests: XCTestCase {
    var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloom-fixture-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.appendingPathComponent("big"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("small/nested"), withIntermediateDirectories: true)

        try Data(count: 1_000_000).write(to: fixture.appendingPathComponent("big/blob.bin"))
        try Data(count: 50_000).write(to: fixture.appendingPathComponent("small/nested/tiny.bin"))
        try Data(count: 10_000).write(to: fixture.appendingPathComponent("root.bin"))

        // Symlink pointing back at the fixture root — following it would loop.
        try fm.createSymbolicLink(
            at: fixture.appendingPathComponent("loop"),
            withDestinationURL: fixture
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    func testSizesAggregateAndSymlinksAreNotFollowed() async throws {
        let progress = ScanProgress()
        let root = await DiskScanner.scan(url: fixture, progress: progress)

        XCTAssertTrue(root.isDirectory)
        // Root size equals the sum of its children (aggregation invariant).
        XCTAssertEqual(root.size, root.children.reduce(0) { $0 + $1.size })

        // Allocated sizes are block-rounded, so compare with tolerance.
        let big = try XCTUnwrap(root.children.first { $0.name == "big" })
        XCTAssertGreaterThanOrEqual(big.size, 1_000_000)
        XCTAssertLessThan(big.size, 1_200_000)

        // The symlink is a leaf, not a directory subtree — no infinite loop,
        // and its size is tiny (the link itself), not the target's.
        let loop = try XCTUnwrap(root.children.first { $0.name == "loop" })
        XCTAssertTrue(loop.children.isEmpty)
        XCTAssertLessThan(loop.size, 4096)

        // Children sorted by size, descending.
        let sizes = root.children.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted(by: >))

        let snap = progress.snapshot
        XCTAssertGreaterThanOrEqual(snap.items, 5)
        XCTAssertGreaterThanOrEqual(snap.bytes, 1_060_000)
        XCTAssertEqual(snap.skipped, 0)
    }

    func testUnreadableDirectoryIsSkippedNotFatal() async throws {
        let locked = fixture.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let progress = ScanProgress()
        let root = await DiskScanner.scan(url: fixture, progress: progress)

        XCTAssertNotNil(root.children.first { $0.name == "locked" })
        XCTAssertEqual(progress.snapshot.skipped, 1)
    }

    func testNegativeDeviceIDsDoNotTrap() {
        // devfs reports a negative st_dev (Int32); a lossy UInt64 conversion
        // crashed the whole-disk scan the moment it stat'ed /dev.
        XCTAssertNotNil(DiskScanner.identity(of: "/dev"))
        XCTAssertNotNil(DiskScanner.identity(of: "/"))
        XCTAssertNotEqual(DiskScanner.identity(of: "/dev")?.dev, DiskScanner.identity(of: "/")?.dev)
    }

    func testVisitedDirectoriesClaimIsOnceOnly() {
        // Firmlinks expose one directory under two paths; the second visit
        // must be refused or a whole-disk scan double-counts everything.
        let visited = VisitedInodes()
        let id = DevIno(dev: 1, ino: 42)
        XCTAssertTrue(visited.claim(id))
        XCTAssertFalse(visited.claim(id))
        XCTAssertTrue(visited.claim(DevIno(dev: 1, ino: 43)))
    }

    func testHardlinkedFilesCountOnce() async throws {
        // rsync --link-dest style snapshot farms hardlink the same file into
        // hundreds of directories; counting each link multiplied 12 GB of
        // transcripts into 2.5 TB. du semantics: first link counts, rest don't.
        let fm = FileManager.default
        let original = fixture.appendingPathComponent("big/blob.bin")
        try fm.createDirectory(at: fixture.appendingPathComponent("snap1"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("snap2"), withIntermediateDirectories: true)
        try fm.linkItem(at: original, to: fixture.appendingPathComponent("snap1/blob.bin"))
        try fm.linkItem(at: original, to: fixture.appendingPathComponent("snap2/blob.bin"))

        let root = await DiskScanner.scan(url: fixture, progress: ScanProgress())

        // ~1 MB counted once, not three times.
        XCTAssertLessThan(root.size, 1_500_000)
        XCTAssertGreaterThanOrEqual(root.size, 1_060_000)
    }

    func testDetachSubtractsSizesUpTheChain() async throws {
        let progress = ScanProgress()
        let root = await DiskScanner.scan(url: fixture, progress: progress)
        let big = try XCTUnwrap(root.children.first { $0.name == "big" })
        let before = root.size

        big.detach()

        XCTAssertEqual(root.size, before - big.size)
        XCTAssertNil(root.children.first { $0.name == "big" })
    }
}
