import SwiftUI

struct SettingsView: View {
    @Bindable var prefs = Prefs.shared
    @State private var fullDiskAccess = false

    var body: some View {
        Form {
            Section {
                Toggle("Scan as administrator", isOn: $prefs.adminScan)
                Text("Runs scans with root privileges so folders owned by other users and the system are included. macOS asks for your password once per scan.")
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
        .onAppear { fullDiskAccess = prefs.hasFullDiskAccess }
    }
}
