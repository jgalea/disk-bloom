import SwiftUI

struct WelcomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                Text("Disk Bloom")
                    .font(.largeTitle.weight(.bold))
                Text("Pick a disk or folder to see where your space went.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.volumes) { volume in
                        Button {
                            model.scan(url: volume.url)
                        } label: {
                            VolumeRow(volume: volume)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: 460, maxHeight: 380)

            VStack(spacing: 12) {
                Button("Scan a Folder…") { pickFolder() }
                    .controlSize(.large)
                    .keyboardShortcut("o")
                Toggle(isOn: Bindable(Prefs.shared).adminScan) {
                    Label("Scan as administrator", systemImage: "lock.shield")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .help("Runs the scan with administrator privileges so protected folders are included. You'll be asked for your password.")
            }

            if !Prefs.shared.hasFullDiskAccess {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tired of per-folder permission pop-ups?")
                            .font(.callout.weight(.semibold))
                        Text("Grant Disk Bloom Full Disk Access once and macOS stops asking. Quit and reopen the app after granting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Open Settings") { Prefs.shared.openFullDiskAccessSettings() }
                }
                .padding(12)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 560)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            model.scan(url: url)
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "internaldrive.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(volume.name)
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(formatBytes(volume.available)) free of \(formatBytes(volume.total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if volume.purgeable > 1_000_000_000 {
                            Text("+ \(formatBytes(volume.purgeable)) purgeable")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Space macOS can free automatically: local snapshots, caches, offloaded files.")
                        }
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * CGFloat(volume.used) / CGFloat(max(volume.total, 1)))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ScanningView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning…")
                .font(.title2.weight(.semibold))
            VStack(spacing: 4) {
                Text("\(model.progress.items.formatted()) items")
                    .monospacedDigit()
                Text(formatBytes(model.progress.bytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
