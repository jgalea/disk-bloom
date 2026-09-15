import XCTest
@testable import BloomCore

final class AdvisorTests: XCTestCase {
    private let home = NSHomeDirectory()

    func testKnownToolDirectoriesAreRecognized() throws {
        let derived = try XCTUnwrap(Advisor.advice(for: home + "/Library/Developer/Xcode/DerivedData"))
        XCTAssertEqual(derived.safety, .regenerable)
        XCTAssertNotNil(derived.command)

        let backups = try XCTUnwrap(Advisor.advice(for: home + "/Library/Application Support/MobileSync/Backup"))
        // Device backups can be the only copy, so they must never read as safe.
        XCTAssertEqual(backups.safety, .review)
        XCTAssertNil(backups.command)
    }

    func testUnknownPathsGetNoAdvice() {
        XCTAssertNil(Advisor.advice(for: home + "/Documents/taxes-2026"))
        XCTAssertNil(Advisor.advice(for: "not-an-absolute-path"))
    }

    func testPrefixRuleMatchesContentsOfAContainer() throws {
        let inside = home + "/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img.raw"
        let advice = try XCTUnwrap(Advisor.advice(for: inside))
        XCTAssertEqual(advice.id, "orbstack.vm")
        // The reclaim step is a Docker command, not deleting the image file.
        XCTAssertTrue(try XCTUnwrap(advice.command).contains("docker"))
    }

    func testNamedRuleMatchesAnywhere() throws {
        let advice = try XCTUnwrap(Advisor.advice(for: "/srv/projects/app/node_modules"))
        XCTAssertEqual(advice.id, "node.modules")
        XCTAssertEqual(advice.safety, .regenerable)
    }

    func testMixedCacheFolderIsNotPresentedAsSafe() throws {
        let caches = try XCTUnwrap(Advisor.advice(for: home + "/Library/Caches"))
        XCTAssertEqual(caches.safety, .review)
        XCTAssertNil(caches.command)
    }

    func testMoreSpecificRuleWinsOverTheGeneralCacheRule() throws {
        let brew = try XCTUnwrap(Advisor.advice(for: home + "/Library/Caches/Homebrew"))
        XCTAssertEqual(brew.id, "homebrew.cache")
    }

    func testAdviseReportsOutermostMatchOnlyLargestFirst() {
        let tree = FileNode(
            name: "root", isDirectory: true, size: 0,
            children: [
                FileNode(name: "node_modules", isDirectory: true, size: 0, children: [
                    FileNode(name: "sub", isDirectory: true, size: 0, children: [
                        FileNode(name: "node_modules", isDirectory: true, size: 0, children: [
                            FileNode(name: "x.bin", isDirectory: false, size: 300 << 20)
                        ])
                    ])
                ]),
                FileNode(name: "__pycache__", isDirectory: true, size: 0, children: [
                    FileNode(name: "y.pyc", isDirectory: false, size: 700 << 20)
                ]),
            ],
            rootPath: "/tmp/project"
        )

        let found = Advisor.advise(tree: tree)
        XCTAssertEqual(found.map(\.advice.id), ["python.pycache", "node.modules"])
        // The nested node_modules is inside a match already reported.
        XCTAssertEqual(found.filter { $0.advice.id == "node.modules" }.count, 1)
    }

    func testAdviseIgnoresSmallDirectories() {
        let tree = FileNode(
            name: "root", isDirectory: true, size: 0,
            children: [FileNode(name: "node_modules", isDirectory: true, size: 0, children: [
                FileNode(name: "tiny.bin", isDirectory: false, size: 1024)
            ])],
            rootPath: "/tmp/project"
        )
        XCTAssertTrue(Advisor.advise(tree: tree).isEmpty)
    }
}
