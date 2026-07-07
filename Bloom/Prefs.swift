import AppKit
import Observation
import SwiftUI

/// App-wide preferences and capability checks, shared by every scan window
/// and the Settings scene.
@MainActor
@Observable
final class Prefs {
    static let shared = Prefs()

    var adminScan: Bool = UserDefaults.standard.bool(forKey: "adminScan") {
        didSet { UserDefaults.standard.set(adminScan, forKey: "adminScan") }
    }

    /// Full Disk Access makes macOS stop showing per-folder privacy prompts
    /// (Desktop, Documents, Downloads, Mail, …) during scans. The TCC
    /// database is only readable with the grant, so probing it is the check.
    var hasFullDiskAccess: Bool {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return false
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
