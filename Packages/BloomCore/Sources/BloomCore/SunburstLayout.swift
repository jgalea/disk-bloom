import Foundation

/// One drawable arc. Angles are radians, clockwise from 12 o'clock
/// (i.e. already offset by -π/2 relative to standard math angles).
public struct Segment: Sendable, Identifiable {
    public let node: FileNode?          // nil for an aggregated "smaller items" arc
    public let parent: FileNode         // owner of the slot this arc occupies
    public let ring: Int                // 0 = innermost ring (children of focus)
    public let start: Double
    public let end: Double
    public let hue: Double              // 0..<1, inherited down the tree
    public let aggregatedCount: Int     // >0 only for aggregated arcs
    public let aggregatedSize: Int64

    public var id: String {
        if let node { return "\(ObjectIdentifier(node).hashValue)" }
        return "agg-\(ObjectIdentifier(parent).hashValue)-\(ring)"
    }

    public var span: Double { end - start }
}

public enum SunburstLayout {
    public static let ringCount = 5
    /// Arcs narrower than this collapse into one gray "smaller items" arc per parent.
    public static let minSpan: Double = 0.006

    /// Lay out the descendants of `focus` into `ringCount` rings.
    public static func segments(focus: FileNode) -> [Segment] {
        guard focus.size > 0 else { return [] }
        var result: [Segment] = []
        layoutChildren(
            of: focus, ring: 0, start: 0, end: 2 * .pi, into: &result
        )
        return result
    }

    private static func layoutChildren(
        of node: FileNode, ring: Int, start: Double, end: Double,
        into result: inout [Segment]
    ) {
        guard ring < ringCount, node.size > 0, !node.children.isEmpty else { return }
        let span = end - start
        var cursor = start
        var aggregatedSize: Int64 = 0
        var aggregatedCount = 0

        for child in node.children {
            let childSpan = span * Double(child.size) / Double(node.size)
            if childSpan < minSpan || child.size <= 0 {
                aggregatedSize += child.size
                aggregatedCount += 1
                continue
            }
            // Hue follows the segment's own angular midpoint, so the wheel is
            // a continuous rainbow and children shade within their parent's range.
            let hue = (cursor + childSpan / 2) / (2 * .pi)
            result.append(Segment(
                node: child, parent: node, ring: ring,
                start: cursor, end: cursor + childSpan,
                hue: hue, aggregatedCount: 0, aggregatedSize: 0
            ))
            if child.isDirectory {
                layoutChildren(
                    of: child, ring: ring + 1, start: cursor, end: cursor + childSpan,
                    into: &result
                )
            }
            cursor += childSpan
        }

        if aggregatedCount > 0 {
            let aggSpan = span * Double(aggregatedSize) / Double(node.size)
            result.append(Segment(
                node: nil, parent: node, ring: ring,
                start: cursor, end: cursor + aggSpan,
                hue: 0, aggregatedCount: aggregatedCount, aggregatedSize: aggregatedSize
            ))
        }
    }

    /// Inverse map: point in chart space → segment. `radius` is the outer
    /// radius of the chart; the center disc occupies `centerFraction` of it.
    public static func hitTest(
        point: CGPoint, center: CGPoint, radius: Double,
        centerFraction: Double, segments: [Segment]
    ) -> Segment? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let innerRadius = radius * centerFraction
        guard distance >= innerRadius, distance <= radius else { return nil }

        let ringWidth = (radius - innerRadius) / Double(ringCount)
        let ring = min(Int((distance - innerRadius) / ringWidth), ringCount - 1)

        // atan2 in screen coords, rotated so 0 is at 12 o'clock, clockwise.
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        return segments.first { $0.ring == ring && angle >= $0.start && angle < $0.end }
    }
}
