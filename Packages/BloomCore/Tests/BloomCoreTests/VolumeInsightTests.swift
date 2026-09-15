import XCTest
@testable import BloomCore

final class VolumeInsightTests: XCTestCase {
    func testNothingHeldBackGivesNoExplanation() {
        let insight = VolumeInsight(purgeableBytes: 0, localSnapshots: [])
        XCTAssertFalse(insight.holdsSpaceBack)
        XCTAssertNil(insight.explanation)
    }

    func testSnapshotsAreExplainedWithCorrectGrammar() throws {
        let one = VolumeInsight(purgeableBytes: 0, localSnapshots: ["com.apple.TimeMachine.2026-09-15-185736.local"])
        XCTAssertTrue(try XCTUnwrap(one.explanation).contains("1 local Time Machine snapshot is"))

        let two = VolumeInsight(purgeableBytes: 0, localSnapshots: ["a", "b"])
        XCTAssertTrue(try XCTUnwrap(two.explanation).contains("2 local Time Machine snapshots are"))
    }

    func testPurgeableAndSnapshotsCombine() throws {
        let insight = VolumeInsight(purgeableBytes: 5 << 30, localSnapshots: ["a"])
        let explanation = try XCTUnwrap(insight.explanation)
        XCTAssertTrue(explanation.contains("snapshot"))
        XCTAssertTrue(explanation.contains("purgeable"))
    }

    func testMeasureOnBootVolumeDoesNotThrowOrReturnNegatives() {
        let insight = VolumeInsight.measure()
        XCTAssertGreaterThanOrEqual(insight.purgeableBytes, 0)
        XCTAssertEqual(insight.localSnapshots.filter { !$0.hasPrefix("com.apple.TimeMachine.") }.count, 0)
    }
}
