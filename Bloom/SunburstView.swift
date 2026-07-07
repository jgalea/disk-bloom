import BloomCore
import SwiftUI

enum ChartMetrics {
    static let centerFraction = 0.30
    static let padding: CGFloat = 24

    static func radius(in size: CGSize) -> Double {
        Double(min(size.width, size.height) / 2 - padding)
    }

    static func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

/// Pure renderer — no gestures, usable by ImageRenderer for snapshots.
/// When a `transition` is in flight, arcs interpolate from their position in
/// the previous layout (compressed inside / expanded around the zoom window)
/// to their final one.
struct SunburstChart: View {
    let segments: [Segment]
    let hoveredID: String?
    var transition: FocusTransition?
    var progress: Double = 1

    var body: some View {
        Canvas { context, size in
            let center = ChartMetrics.center(in: size)
            let radius = ChartMetrics.radius(in: size)
            guard radius > 40 else { return }
            let innerRadius = radius * ChartMetrics.centerFraction
            let ringWidth = (radius - innerRadius) / Double(SunburstLayout.ringCount)
            let ringGap = min(2.5, ringWidth * 0.06)

            for segment in segments {
                let isHovered = segment.id == hoveredID

                var startRadians = segment.start
                var endRadians = segment.end
                var ring = Double(segment.ring)
                if let transition, progress < 1 {
                    let initial = ZoomTransition.initialState(
                        finalStart: segment.start, finalEnd: segment.end,
                        direction: transition.direction, window: transition.window
                    )
                    startRadians = initial.start + (segment.start - initial.start) * progress
                    endRadians = initial.end + (segment.end - initial.end) * progress
                    ring += initial.ringOffset * (1 - progress)
                }

                let r0 = innerRadius + ring * ringWidth
                // Hovered arcs pop outward slightly, DaisyDisk-style.
                let r1 = r0 + ringWidth - ringGap + (isHovered ? min(4, ringGap * 2) : 0)
                guard r1 > innerRadius + 0.5, r0 < radius + ringWidth else { continue }

                // A hair of angular breathing room between wide siblings keeps
                // the wheel crisp without erasing thin slivers.
                let span = endRadians - startRadians
                let angularGap = min(0.0035, span * 0.12)
                let start = Angle(radians: startRadians - .pi / 2 + angularGap)
                let end = Angle(radians: endRadians - .pi / 2 - angularGap)

                var path = Path()
                path.addArc(center: center, radius: r1, startAngle: start, endAngle: end, clockwise: false)
                path.addArc(center: center, radius: max(r0, innerRadius), startAngle: end, endAngle: start, clockwise: true)
                path.closeSubpath()

                let (inner, outer) = colors(for: segment, hovered: isHovered)
                context.fill(path, with: .radialGradient(
                    Gradient(colors: [inner, outer]),
                    center: center, startRadius: max(r0, innerRadius), endRadius: max(r1, innerRadius + 1)
                ))
            }
        }
    }

    /// Each arc shades from a deeper inner edge to a brighter rim, which
    /// gives the wheel depth without strokes or shadows.
    private func colors(for segment: Segment, hovered: Bool) -> (inner: Color, outer: Color) {
        // Aggregated arcs and plain files render gray; folders carry the color.
        if segment.node == nil || segment.node?.isDirectory == false {
            let base = hovered ? 0.80 : 0.66
            return (Color(white: base - 0.06), Color(white: base + 0.06))
        }
        let ring = Double(segment.ring)
        let saturation = max(0.38, 0.85 - ring * 0.08)
        let brightness = min(1.0, (0.80 + ring * 0.03) + (hovered ? 0.13 : 0))
        return (
            Color(hue: segment.hue, saturation: min(1, saturation + 0.10), brightness: brightness - 0.10),
            Color(hue: segment.hue, saturation: saturation, brightness: brightness + 0.06)
        )
    }
}

/// Interactive wrapper: hover, click-to-zoom, center-to-go-up, context menu.
struct SunburstView: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = ChartMetrics.center(in: size)
            let radius = ChartMetrics.radius(in: size)

            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.transition == nil)) { timeline in
                    SunburstChart(
                        segments: model.segments,
                        hoveredID: model.hovered?.id,
                        transition: model.transition,
                        progress: transitionProgress(at: timeline.date)
                    )
                }
                centerDisc(radius: radius)
                    .position(center)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    model.hovered = SunburstLayout.hitTest(
                        point: point, center: center, radius: radius,
                        centerFraction: ChartMetrics.centerFraction, segments: model.segments
                    )
                case .ended:
                    model.hovered = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location, center: center, radius: radius)
                }
            )
            .contextMenu {
                if let node = model.hovered?.node {
                    contextMenuItems(for: node)
                } else if let focus = model.focus {
                    contextMenuItems(for: focus)
                }
            }
        }
        .accessibilityLabel("Disk usage sunburst chart")
    }

    /// Eased 0→1 progress for the in-flight focus transition; clears the
    /// transition state once it completes.
    private func transitionProgress(at date: Date) -> Double {
        guard let transition = model.transition else { return 1 }
        let raw = min(1, date.timeIntervalSince(transition.startedAt) / FocusTransition.duration)
        if raw >= 1 {
            Task { @MainActor in
                if model.transition?.startedAt == transition.startedAt { model.transition = nil }
            }
            return 1
        }
        return raw * raw * (3 - 2 * raw)
    }

    private func handleTap(at point: CGPoint, center: CGPoint, radius: Double) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < radius * ChartMetrics.centerFraction {
            model.goUp()
            return
        }
        guard let segment = SunburstLayout.hitTest(
            point: point, center: center, radius: radius,
            centerFraction: ChartMetrics.centerFraction, segments: model.segments
        ) else { return }
        if let node = segment.node, node.isDirectory, !node.children.isEmpty {
            model.setFocus(node)
        }
    }

    @ViewBuilder
    private func centerDisc(radius: Double) -> some View {
        let discRadius = radius * ChartMetrics.centerFraction - 4
        ZStack {
            Circle()
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 6)
            VStack(spacing: 4) {
                if let segment = model.hovered {
                    if let node = segment.node {
                        Text(node.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(formatBytes(node.size))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let focus = model.focus, focus.size > 0 {
                            Text(percentText(node.size, of: focus.size))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("\(segment.aggregatedCount) smaller items")
                            .font(.headline)
                        Text(formatBytes(segment.aggregatedSize))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else if let focus = model.focus {
                    Text(focus.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(formatBytes(focus.size))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if focus.parent != nil {
                        Text("Click center to go up")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(width: discRadius * 2 - 8)
        }
        .frame(width: discRadius * 2, height: discRadius * 2)
    }

    @ViewBuilder
    private func contextMenuItems(for node: FileNode) -> some View {
        NodeContextMenu(model: model, node: node)
    }
}

/// Shared context menu for chart segments, sidebar rows and search results.
struct NodeContextMenu: View {
    let model: AppModel
    let node: FileNode

    var body: some View {
        Text("\(node.name) — \(formatBytes(node.size))")
        Divider()
        if !node.isDirectory {
            Button("Quick Look") { model.quickLook(node) }
        }
        Button("Reveal in Finder") { model.revealInFinder(node) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
        Divider()
        Button(model.isCollected(node) ? "Remove from Collector" : "Add to Collector") {
            model.toggleCollected(node)
        }
        Button("Move to Trash", role: .destructive) {
            Task { await model.moveToTrash(node) }
        }
    }
}

func percentText(_ part: Int64, of whole: Int64) -> String {
    let pct = 100 * Double(part) / Double(whole)
    return pct < 0.1 ? "< 0.1%" : String(format: "%.1f%%", pct)
}
