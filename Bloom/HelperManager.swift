import Foundation
import Observation
import ServiceManagement

/// Manages the privileged bloom-helper daemon (SMAppService). Once the user
/// approves it in System Settings → Login Items, admin scans run through XPC
/// with no per-scan password prompt.
@MainActor
@Observable
final class HelperManager {
    static let shared = HelperManager()

    private let service = SMAppService.daemon(plistName: BloomHelper.plistName)
    var status: SMAppService.Status = .notRegistered

    init() {
        refresh()
    }

    func refresh() {
        status = service.status
    }

    var isActive: Bool { status == .enabled }

    /// Register the daemon; returns a user-facing instruction when approval
    /// is still needed, nil when the helper is active.
    func enable() -> String? {
        refresh()
        if status == .enabled { return nil }
        do {
            try service.register()
        } catch {
            refresh()
            if status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return "Approve Disk Bloom under Login Items → Allow in Background, then try again."
            }
            return "Couldn't register the background helper: \(error.localizedDescription)"
        }
        refresh()
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "Approve Disk Bloom under Login Items → Allow in Background, then try again."
        }
        return status == .enabled ? nil : "Background helper isn't available (status \(status.rawValue))."
    }

    func disable() {
        try? service.unregister()
        refresh()
    }
}
