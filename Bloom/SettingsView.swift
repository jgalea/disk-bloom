import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var prefs = Prefs.shared
    @State private var fullDiskAccess = false
    @State private var helperActive = false
    @State private var helperMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Scan as administrator", isOn: $prefs.adminScan)
                Text("Runs scans with root privileges so folders owned by other users and the system are included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Background helper") {
                    if helperActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Enable…") {
                            helperMessage = HelperManager.shared.enable()
                            helperActive = HelperManager.shared.isActive
                        }
                    }
                }
                Text(helperActive
                    ? "Administrator scans run through the approved helper — no password prompts."
                    : helperMessage ?? "One-time approval in System Settings lets administrator scans run without a password prompt each time. Without it, macOS asks for your password once per scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded from scans") {
                ExclusionsEditor(prefs: prefs)
            }

            Section {
                LabeledContent("Full Disk Access") {
                    if fullDiskAccess {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") {
                            prefs.openFullDiskAccessSettings()
                        }
                    }
                }
                Text(fullDiskAccess
                    ? "Disk Bloom can scan protected folders (Mail, Messages, Safari data) without permission pop-ups."
                    : "Granting Full Disk Access stops macOS's per-folder permission pop-ups and lets the app see protected folders. Add Disk Bloom in System Settings → Privacy & Security → Full Disk Access, then quit and reopen the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            fullDiskAccess = prefs.hasFullDiskAccess
            HelperManager.shared.refresh()
            helperActive = HelperManager.shared.isActive
        }
    }
}

/// Folders the scanner skips entirely. An excluded tree is never opened, so
/// it costs nothing and contributes nothing to any parent's size.
private struct ExclusionsEditor: View {
    @Bindable var prefs: Prefs
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if prefs.exclusions.isEmpty {
                Text("Nothing is excluded. Add a folder to keep it out of every scan, such as a backup mirror whose size you have already decided about.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                List(selection: $selection) {
                    ForEach(prefs.exclusions, id: \.self) { path in
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(height: 96)
                .border(.quaternary)
            }
            HStack {
                Button("Add Folder…") { choose() }
                Button("Remove") {
                    prefs.removeExclusions(selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { prefs.addExclusion(url.path) }
    }
}
