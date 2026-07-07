import BloomCore
import SwiftUI

/// Largest items inside the focused folder — or search results when a query
/// is active — mirroring the chart.
struct SidebarView: View {
    @Bindable var model: AppModel

    private var searching: Bool {
        model.searchQuery.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        List {
            if searching {
                Section("Results (largest first)") {
                    if model.searchResults.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.searchResults) { node in
                        row(for: node, showPath: true)
                    }
                }
            } else if let focus = model.focus {
                Section("Largest in \(focus.name)") {
                    ForEach(focus.children.prefix(30)) { child in
                        row(for: child, showPath: false)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func row(for node: FileNode, showPath: Bool) -> some View {
        HStack {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showPath {
                    Text(node.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            if model.isCollected(node) {
                Image(systemName: "tray.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(formatBytes(node.size))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory, !node.children.isEmpty {
                model.setFocus(node)
                model.searchQuery = ""
            } else if let parent = node.parent {
                model.setFocus(parent)
                model.searchQuery = ""
            }
        }
        .contextMenu {
            NodeContextMenu(model: model, node: node)
        }
    }
}
