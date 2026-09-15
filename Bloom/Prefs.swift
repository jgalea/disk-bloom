import AppKit
import BloomCore
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

    /// Paths the scanner never descends into. Stored as written so the
    /// Settings list shows what was typed, normalized only at scan time.
    var exclusions: [String] = UserDefaults.standard.stringArray(forKey: "exclusions") ?? [] {
        didSet { UserDefaults.standard.set(exclusions, forKey: "exclusions") }
    }

    var exclusionSet: Exclusions { Exclusions(paths: exclusions) }

    func addExclusion(_ path: String) {
        guard let normalized = Exclusions.normalize(path), !exclusions.contains(normalized) else { return }
        exclusions.append(normalized)
    }

    func removeExclusions(_ paths: Set<String>) {
        exclusions.removeAll { paths.contains($0) }
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
