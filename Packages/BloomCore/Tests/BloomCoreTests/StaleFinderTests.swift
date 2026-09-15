import XCTest
@testable import BloomCore

final class StaleFinderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var longAgo: Int64 { Int64(now.timeIntervalSince1970 - 200 * 24 * 60 * 60) }
    private var yesterday: Int64 { Int64(now.timeIntervalSince1970 - 24 * 60 * 60) }

    private func tree(_ children: [FileNode]) -> FileNode {
        FileNode(name: "root", isDirectory: true, size: 0, children: children, rootPath: "/tmp/root")
    }

    func testColdAndLargeIsReported() {
        let root = tree([
            FileNode(name: "backup.img", isDirectory: false, size: 11 << 30, modified: longAgo),
            FileNode(name: "active.img", isDirectory: false, size: 12 << 30, modified: yesterday),
        ])

        let stale = StaleFinder.stale(tree: root, now: now)
        XCTAssertEqual(stale.map(\.name), ["backup.img"])
    }

    func testSmallColdFilesAreIgnored() {
        let root = tree([FileNode(name: "note.txt", isDirectory: false, size: 12, modified: longAgo)])
        XCTAssertTrue(StaleFinder.stale(tree: root, now: now).isEmpty)
    }

    func testUnknownAgeIsNeverCalledStale() {
        let root = tree([FileNode(name: "mystery.bin", isDirectory: false, size: 5 << 30)])
        XCTAssertTrue(StaleFinder.stale(tree: root, now: now).isEmpty)
    }

    func testOnlyTheOutermostColdNodeIsReported() {
        let root = tree([
            FileNode(name: "archive", isDirectory: true, size: 0, modified: longAgo, children: [
                FileNode(name: "a.bin", isDirectory: false, size: 3 << 30, modified: longAgo),
                FileNode(name: "b.bin", isDirectory: false, size: 3 << 30, modified: longAgo),
            ])
        ])

        let stale = StaleFinder.stale(tree: root, now: now)
        XCTAssertEqual(stale.map(\.name), ["archive"])
    }

    func testAFreshFileKeepsItsWholeFolderOutOfTheList() {
        let root = tree([
            FileNode(name: "project", isDirectory: true, size: 0, modified: longAgo, children: [
                FileNode(name: "old.bin", isDirectory: false, size: 8 << 30, modified: longAgo),
                FileNode(name: "touched-today.txt", isDirectory: false, size: 1024, modified: yesterday),
            ])
        ])

        // The folder is live, so it is not offered as a whole; the cold file
        // inside it still is.
        let stale = StaleFinder.stale(tree: root, now: now)
        XCTAssertEqual(stale.map(\.name), ["old.bin"])
    }

    func testTheScanRootItselfIsNeverOffered() {
        let root = FileNode(
            name: "root", isDirectory: true, size: 9 << 30, modified: longAgo, rootPath: "/tmp/root"
        )
        XCTAssertTrue(StaleFinder.stale(tree: root, now: now).isEmpty)
    }
}
