import XCTest
@testable import BloomCore

final class SunburstLayoutTests: XCTestCase {
    func node(_ name: String, size: Int64 = 0, children: [FileNode] = []) -> FileNode {
        FileNode(
            name: name, isDirectory: !children.isEmpty || size == 0,
            size: size, children: children
        )
    }

    func testChildSpansSumToParentSpan() {
        let root = node("root", children: [
            node("a", size: 500),
            node("b", size: 300),
            node("c", size: 200),
        ])
        let segments = SunburstLayout.segments(focus: root)
        let ring0 = segments.filter { $0.ring == 0 }
        XCTAssertEqual(ring0.count, 3)
        let total = ring0.reduce(0.0) { $0 + $1.span }
        XCTAssertEqual(total, 2 * .pi, accuracy: 1e-9)
    }

    func testTinyChildrenAggregate() {
        var children = [node("big", size: 1_000_000)]
        for i in 0..<50 { children.append(node("tiny\(i)", size: 1)) }
        let root = node("root", children: children)

        let segments = SunburstLayout.segments(focus: root)
        let ring0 = segments.filter { $0.ring == 0 }
        let aggregated = ring0.filter { $0.node == nil }
        XCTAssertEqual(aggregated.count, 1)
        XCTAssertEqual(aggregated[0].aggregatedCount, 50)
        XCTAssertEqual(aggregated[0].aggregatedSize, 50)
        XCTAssertEqual(ring0.count, 2) // big + one aggregate arc
    }

    func testNestedRingsStayWithinParentAngles() {
        let root = node("root", children: [
            node("a", size: 0, children: [node("a1", size: 600), node("a2", size: 400)]),
            node("b", size: 1000),
        ])
        let segments = SunburstLayout.segments(focus: root)
        let parentA = segments.first { $0.node?.name == "a" }!
        for child in segments.filter({ $0.ring == 1 }) {
            XCTAssertGreaterThanOrEqual(child.start, parentA.start - 1e-9)
            XCTAssertLessThanOrEqual(child.end, parentA.end + 1e-9)
            // Hue tracks the segment's own midpoint, staying inside the
            // parent's angular (and therefore hue) range.
            XCTAssertEqual(child.hue, (child.start + child.end) / 2 / (2 * .pi), accuracy: 1e-9)
        }
    }

    func testHitTestRoundTrip() {
        let root = node("root", children: [
            node("a", size: 500, children: [node("a1", size: 500)]),
            node("b", size: 300),
            node("c", size: 200),
        ])
        let segments = SunburstLayout.segments(focus: root)
        let center = CGPoint(x: 200, y: 200)
        let radius = 180.0
        let centerFraction = 0.25
        let ringWidth = radius * (1 - centerFraction) / Double(SunburstLayout.ringCount)

        for segment in segments {
            let midAngle = (segment.start + segment.end) / 2
            let midRadius = radius * centerFraction + (Double(segment.ring) + 0.5) * ringWidth
            // Convert back from "clockwise from 12 o'clock" to screen coords.
            let point = CGPoint(
                x: center.x + midRadius * cos(midAngle - .pi / 2),
                y: center.y + midRadius * sin(midAngle - .pi / 2)
            )
            let hit = SunburstLayout.hitTest(
                point: point, center: center, radius: radius,
                centerFraction: centerFraction, segments: segments
            )
            XCTAssertEqual(hit?.id, segment.id, "round-trip failed for \(segment.node?.name ?? "aggregate")")
        }

        // Center disc and outside the chart both miss.
        XCTAssertNil(SunburstLayout.hitTest(
            point: center, center: center, radius: radius,
            centerFraction: centerFraction, segments: segments
        ))
        XCTAssertNil(SunburstLayout.hitTest(
            point: CGPoint(x: 399, y: 399), center: center, radius: radius,
            centerFraction: centerFraction, segments: segments
        ))
    }
}
