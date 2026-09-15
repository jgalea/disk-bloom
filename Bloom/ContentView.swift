import BloomCore
import QuickLook
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var confirmEmptyCollector = false

    var body: some View {
        Group {
            switch model.phase {
            case .welcome:
                WelcomeView(model: model)
            case .scanning:
                ScanningView(model: model)
            case .ready:
                resultView
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .quickLookPreview($model.previewURL)
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var resultView: some View {
        HSplitView {
            SidebarView(model: model)
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 400)
            VStack(spacing: 0) {
                breadcrumbBar
                SunburstView(model: model)
                if !model.collector.isEmpty {
                    collectorBar
                }
                statusBar
            }
            .frame(minWidth: 560, maxWidth: .infinity)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            if let node = model.hovered?.node, !node.isDirectory {
                model.quickLook(node)
                return .handled
            }
            return .ignored
        }
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Search files")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.backToWelcome()
                } label: {
                    Label("New Scan", systemImage: "arrow.counterclockwise")
                }
                .help("Scan another disk or folder")
            }
            ToolbarItem {
                Button {
                    model.goUp()
                } label: {
                    Label("Up", systemImage: "arrow.up")
                }
                .disabled(model.focus?.parent == nil)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Go to enclosing folder (⌘↑)")
            }
            ToolbarItem {
                Button {
                    model.showInsights = true
                } label: {
                    Label("Reclaim", systemImage: "lightbulb")
                }
                .disabled(!model.hasInsights)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("What these folders are, and how to reclaim them (⇧⌘R)")
            }
        }
        .sheet(isPresented: $model.showInsights) {
            InsightsView(model: model)
        }
        .confirmationDialog(
            "Move \(model.collector.count) items (\(formatBytes(model.collectorSize))) to the Trash?",
            isPresented: $confirmEmptyCollector
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.emptyCollectorToTrash() }
            }
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(node.name) { model.setFocus(node) }
                        .buttonStyle(.plain)
                        .font(.callout.weight(node === model.focus ? .semibold : .regular))
                        .foregroundStyle(node === model.focus ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// DaisyDisk-style Collector: items staged for deletion, one confirmation.
    private var collectorBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(.orange)
            Text("\(model.collector.count) collected · \(formatBytes(model.collectorSize))")
                .font(.callout.weight(.medium))
                .monospacedDigit()
            Spacer()
            Button("Clear") { model.collector.removeAll() }
            Button("Move All to Trash", role: .destructive) { confirmEmptyCollector = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quinary)
    }

    private var statusBar: some View {
        HStack {
            if let focus = model.focus {
                Text("\(focus.children.count) items · \(formatBytes(focus.size))")
            }
            Spacer()
            if model.skipped > 0 {
                Label("\(model.skipped) folders skipped (no permission)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Grant Full Disk Access in System Settings → Privacy & Security to scan protected folders.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
