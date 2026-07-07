import BloomCore
import SwiftUI

/// Debug hook: `Bloom --snapshot <dir> --out <png>` scans a directory,
/// renders the sunburst offscreen, writes a PNG, and exits. Used to verify
/// the chart visually from the command line.
enum SnapshotRunner {
    /// `Bloom --uishot <png> [--autoscan <dir>]` waits for the UI to settle,
    /// captures the app's own window content (no screen-recording permission
    /// needed), writes a PNG, and exits.
    @MainActor
    static func captureUIIfRequested(model: AppModel) async {
        let args = CommandLine.arguments
        guard let shotIndex = args.firstIndex(of: "--uishot"), args.count > shotIndex + 1 else { return }
        let output = URL(fileURLWithPath: args[shotIndex + 1])
        let wantsScan = args.contains("--autoscan")

        for _ in 0..<600 {
            let settled = wantsScan ? model.phase == .ready : model.phase == .welcome
            if settled { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(800))

        if let window = NSApp.windows.first(where: { $0.isVisible }),
           let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: output)
            }
        }
        exit(0)
    }

    /// `Bloom --icon <png>` renders the app icon artwork (a synthetic
    /// sunburst on a dark squircle) at 1024×1024 and exits.
    @MainActor
    static func renderIconIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--icon"), args.count > index + 1 else { return }
        let output = URL(fileURLWithPath: args[index + 1])

        // Stylized three-ring sunburst in the app's own color language.
        let ringSpans: [[Double]] = [
            [0.34, 0.22, 0.16, 0.12, 0.10, 0.06],
            [0.20, 0.14, 0.16, 0.10, 0.12, 0.08, 0.09, 0.11],
            [0.12, 0.10, 0.08, 0.09, 0.11, 0.07, 0.08, 0.10, 0.09, 0.16],
        ]
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 232, style: .continuous)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.14))
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let innerRadius = 130.0
                let ringWidth = 90.0
                for (ring, spans) in ringSpans.enumerated() {
                    var cursor = -Double.pi / 2
                    let r0 = innerRadius + Double(ring) * (ringWidth + 12)
                    let r1 = r0 + ringWidth
                    for span in spans {
                        let sweep = span * 2 * .pi * 0.96
                        let start = Angle(radians: cursor)
                        let end = Angle(radians: cursor + sweep)
                        var path = Path()
                        path.addArc(center: center, radius: r1, startAngle: start, endAngle: end, clockwise: false)
                        path.addArc(center: center, radius: r0, startAngle: end, endAngle: start, clockwise: true)
                        path.closeSubpath()
                        let hue = (cursor + sweep / 2 + .pi / 2) / (2 * .pi)
                        let ringD = Double(ring)
                        context.fill(path, with: .color(Color(
                            hue: hue.truncatingRemainder(dividingBy: 1),
                            saturation: 0.80 - ringD * 0.09,
                            brightness: 0.86 + ringD * 0.04
                        )))
                        cursor += span * 2 * .pi
                    }
                }
            }
        }
        .frame(width: 1024, height: 1024)

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        if let cgImage = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: output)
            }
        }
        exit(0)
    }

    @MainActor
    static func runIfRequested() async {
        let args = CommandLine.arguments
        guard let snapIndex = args.firstIndex(of: "--snapshot"), args.count > snapIndex + 1,
              let outIndex = args.firstIndex(of: "--out"), args.count > outIndex + 1
        else { return }

        let target = URL(fileURLWithPath: args[snapIndex + 1])
        let output = URL(fileURLWithPath: args[outIndex + 1])

        let tree = await DiskScanner.scan(url: target, progress: ScanProgress())
        let segments = SunburstLayout.segments(focus: tree)

        let chart = ZStack {
            Color(nsColor: .windowBackgroundColor)
            SunburstChart(segments: segments, hoveredID: nil)
            VStack(spacing: 4) {
                Text(tree.name).font(.headline)
                Text(formatBytes(tree.size)).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 900, height: 900)

        let renderer = ImageRenderer(content: chart)
        renderer.scale = 2
        if let cgImage = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: output)
            }
        }
        exit(0)
    }
}
