import SwiftUI

@main
struct BloomApp: App {
    var body: some Scene {
        // Each window owns its own model, so ⌘N opens an independent scan.
        WindowGroup {
            WindowRoot()
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}

struct WindowRoot: View {
    @State private var model = AppModel()

    var body: some View {
        ContentView(model: model)
            .task {
                SnapshotRunner.renderIconIfRequested()
                await SnapshotRunner.runIfRequested()
                await SnapshotRunner.captureUIIfRequested(model: model)
            }
    }
}
