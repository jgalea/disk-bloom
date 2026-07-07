import Foundation

/// Geometry for animating a focus change. When zooming into a node, every
/// segment of the NEW layout starts compressed inside the angular window that
/// node occupied in the OLD layout, then expands to its final position (and
/// the reverse when zooming out). Interpolate angles and ring offset with an
/// eased progress and the wheel appears to fly in or out, DaisyDisk-style.
public struct AngularWindow: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let ring: Int

    public init(start: Double, end: Double, ring: Int) {
        self.start = start
        self.end = end
        self.ring = ring
    }

    public var span: Double { end - start }
}

public enum ZoomTransition {
    public enum Direction: Sendable {
        case zoomIn   // new focus is a descendant of the old focus
        case zoomOut  // new focus is an ancestor of the old focus
    }

    /// Where a segment of the final layout starts the animation.
    /// `ringOffset` is added to the segment's ring (fractionally, during
    /// interpolation); angles are in final-layout radians.
    public static func initialState(
        finalStart: Double, finalEnd: Double,
        direction: Direction, window: AngularWindow
    ) -> (start: Double, end: Double, ringOffset: Double) {
        let full = 2 * Double.pi
        switch direction {
        case .zoomIn:
            // The whole new wheel starts squeezed inside the old window.
            return (
                window.start + finalStart / full * window.span,
                window.start + finalEnd / full * window.span,
                Double(window.ring + 1)
            )
        case .zoomOut:
            // Content that filled the old wheel starts expanded from the
            // window it now occupies, i.e. the inverse mapping.
            return (
                (finalStart - window.start) / window.span * full,
                (finalEnd - window.start) / window.span * full,
                -Double(window.ring + 1)
            )
        }
    }

    /// Classify a focus change. Returns nil when the two nodes aren't in an
    /// ancestor/descendant relationship (no animated path; just swap).
    public static func direction(from old: FileNode, to new: FileNode) -> Direction? {
        var node = new.parent
        while let n = node {
            if n === old { return .zoomIn }
            node = n.parent
        }
        node = old.parent
        while let n = node {
            if n === new { return .zoomOut }
            node = n.parent
        }
        return nil
    }
}
