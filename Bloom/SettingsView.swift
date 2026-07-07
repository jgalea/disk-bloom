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
