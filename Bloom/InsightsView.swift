import AppKit
import BloomCore
import SwiftUI

/// What the chart cannot say on its own: which wedges belong to a tool, how
/// to reclaim those properly, what has gone cold, and why free space may not
/// move by as much as you just deleted.
struct InsightsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.hasInsights {
                List {
                    if let note = model.volumeInsight?.explanation {
                        Section("Free space") {
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 2)
                        }
                    }
                    if !model.advice.isEmpty {
                        Section("Owned by a tool") {
                            ForEach(model.advice, id: \.node.id) { entry in
                                adviceRow(node: entry.node, advice: entry.advice)
                            }
                        }
                    }
                    if !model.staleNodes.isEmpty {
                        Section("Untouched for months") {
                            ForEach(model.staleNodes, id: \.id) { node in
                                staleRow(node)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                emptyState
            }
        }
        .frame(width: 620, height: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaim Space")
                    .font(.headline)
                Text("Findings for \(model.root?.path ?? "this scan")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Nothing obvious to reclaim here")
                .font(.headline)
            Text("No tool-owned folders, and nothing large has gone untouched.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func adviceRow(node: FileNode, advice: Advice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.name).font(.body.weight(.medium))
                safetyBadge(advice.safety)
                Spacer()
                Text(formatted(node.size))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(advice.owner)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(advice.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let command = advice.command {
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Button(copied == advice.id ? "Copied" : "Copy") { copy(command, id: advice.id) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            revealButton(node)
        }
        .padding(.vertical, 6)
    }

    private func staleRow(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.name).font(.body.weight(.medium))
                Spacer()
                Text(formatted(node.size))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(ageDescription(node))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(node.path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            revealButton(node)
        }
        .padding(.vertical, 4)
    }

    private func safetyBadge(_ safety: Advice.Safety) -> some View {
        let (label, color): (String, Color) = switch safety {
        case .regenerable: ("Regenerable", .green)
        case .review: ("Check first", .orange)
        case .systemManaged: ("macOS handles it", .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func revealButton(_ node: FileNode) -> some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == id { copied = nil }
        }
    }

    private func ageDescription(_ node: FileNode) -> String {
        guard let age = node.age() else { return "Last modified: unknown" }
        let days = Int(age / 86_400)
        if days >= 365 {
            let years = days / 365
            return "Untouched for over \(years) year\(years == 1 ? "" : "s")"
        }
        let months = max(1, days / 30)
        return "Untouched for about \(months) month\(months == 1 ? "" : "s")"
    }

    private func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
