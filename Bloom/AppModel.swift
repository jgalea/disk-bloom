import AppKit
import BloomCore
import Observation
import SwiftUI

struct VolumeInfo: Identifiable {
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let purgeable: Int64
    var id: URL { url }
    var used: Int64 { total - available }
}

struct FocusTransition {
    let direction: ZoomTransition.Direction
    let window: AngularWindow
    let startedAt: Date

    static let duration: TimeInterval = 0.35
}

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case welcome
        case scanning
        case ready
    }

    var phase: Phase = .welcome
    var volumes: [VolumeInfo] = []
    var progress = ScanSnapshot(items: 0, bytes: 0, skipped: 0)
    var root: FileNode?
    var focus: FileNode?
    var segments: [Segment] = []
    var hovered: Segment?
    var skipped = 0
    var errorMessage: String?
    var transition: FocusTransition?
    var previewURL: URL?
    var collector: [FileNode] = []
    var searchQuery = "" {
        didSet { scheduleSearch() }
    }
    var searchResults: [FileNode] = []

    private var scanProgress: ScanProgress?
    private var searchTask: Task<Void, Never>?

    init() {
        refreshVolumes()
        // Debug hook: `Bloom --autoscan <path>` jumps straight into a scan.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--autoscan"), args.count > index + 1 {
            scan(url: URL(fileURLWithPath: args[index + 1]))
        }
    }

    func refreshVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []
        volumes = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  let total = values.volumeTotalCapacity, total > 0
            else { return nil }
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            return VolumeInfo(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                total: Int64(total),
                available: available,
                purgeable: max(0, important - available)
            )
        }
    }

    func scan(url: URL) {
        if Prefs.shared.adminScan {
            scanAsAdministrator(url: url)
            return
        }
        phase = .scanning
        progress = ScanSnapshot(items: 0, bytes: 0, skipped: 0)
        let scanProgress = ScanProgress()
        self.scanProgress = scanProgress

        Task { [weak self] in
            while self?.phase == .scanning {
                self?.progress = scanProgress.snapshot
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        Task.detached(priority: .userInitiated) {
            let tree = await DiskScanner.scan(url: url, progress: scanProgress)
            await MainActor.run { [weak self] in
                self?.finishScan(tree: tree, skipped: scanProgress.snapshot.skipped)
            }
        }
    }

    /// DaisyDisk-style admin scan: run the embedded bloom-scan helper with
    /// administrator privileges (system password prompt), poll its progress
    /// file, then load the serialized tree it wrote.
    private func scanAsAdministrator(url: URL) {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "bloom-scan")?.path else {
            errorMessage = "The bloom-scan helper is missing from the app bundle."
            return
        }
        phase = .scanning
        progress = ScanSnapshot(items: 0, bytes: 0, skipped: 0)

        let token = UUID().uuidString
        let treeFile = NSTemporaryDirectory() + "bloom-admin-\(token).tree"
        let progressFile = NSTemporaryDirectory() + "bloom-admin-\(token).progress"

        Task { [weak self] in
            while self?.phase == .scanning {
                if let text = try? String(contentsOfFile: progressFile, encoding: .utf8) {
                    let parts = text.split(separator: " ").compactMap { Int64($0) }
                    if parts.count == 3 {
                        self?.progress = ScanSnapshot(items: Int(parts[0]), bytes: parts[1], skipped: Int(parts[2]))
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                try? FileManager.default.removeItem(atPath: treeFile)
                try? FileManager.default.removeItem(atPath: progressFile)
            }
            func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let shell = [shellQuote(helper), shellQuote(url.path), shellQuote(treeFile), "--progress", shellQuote(progressFile)]
                .joined(separator: " ")
            let script = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
                + " with administrator privileges"
                + " with prompt \"Disk Bloom wants to scan protected folders as administrator.\""

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.phase = .welcome
                }
                return
            }

            if process.terminationStatus != 0 {
                let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let cancelled = stderr.contains("-128") || stderr.localizedCaseInsensitiveContains("canceled")
                await MainActor.run { [weak self] in
                    if !cancelled { self?.errorMessage = "Administrator scan failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))" }
                    self?.phase = .welcome
                }
                return
            }

            do {
                let (tree, skipped) = try TreeSerializer.read(from: URL(fileURLWithPath: treeFile))
                await MainActor.run { [weak self] in
                    self?.finishScan(tree: tree, skipped: skipped)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Couldn't load the scan result: \(error.localizedDescription)"
                    self?.phase = .welcome
                }
            }
        }
    }

    private func finishScan(tree: FileNode, skipped: Int) {
        root = tree
        self.skipped = skipped
        setFocus(tree)
        transition = nil
        phase = .ready
        runDebugActions()
    }

    func setFocus(_ node: FileNode) {
        let oldFocus = focus
        let oldSegments = segments
        focus = node
        hovered = nil
        segments = SunburstLayout.segments(focus: node)
        transition = nil

        guard let oldFocus, oldFocus !== node,
              let direction = ZoomTransition.direction(from: oldFocus, to: node)
        else { return }
        switch direction {
        case .zoomIn:
            if let seg = oldSegments.first(where: { $0.node === node }) {
                transition = FocusTransition(
                    direction: .zoomIn,
                    window: AngularWindow(start: seg.start, end: seg.end, ring: seg.ring),
                    startedAt: .now
                )
            }
        case .zoomOut:
            if let seg = segments.first(where: { $0.node === oldFocus }) {
                transition = FocusTransition(
                    direction: .zoomOut,
                    window: AngularWindow(start: seg.start, end: seg.end, ring: seg.ring),
                    startedAt: .now
                )
            }
        }
    }

    func goUp() {
        guard let parent = focus?.parent else { return }
        setFocus(parent)
    }

    func backToWelcome() {
        phase = .welcome
        root = nil
        focus = nil
        segments = []
        hovered = nil
        collector = []
        searchQuery = ""
        refreshVolumes()
    }

    var breadcrumbs: [FileNode] {
        guard let focus else { return [] }
        return focus.ancestors + [focus]
    }

    // MARK: - Actions on nodes

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func quickLook(_ node: FileNode) {
        previewURL = node.url
    }

    func isCollected(_ node: FileNode) -> Bool {
        collector.contains { $0 === node }
    }

    func toggleCollected(_ node: FileNode) {
        if isCollected(node) {
            collector.removeAll { $0 === node }
        } else {
            collector.append(node)
        }
    }

    var collectorSize: Int64 {
        collector.reduce(0) { $0 + $1.size }
    }

    func emptyCollectorToTrash() async {
        for node in collector {
            await moveToTrash(node)
        }
        // Trashed nodes were detached; anything still parented failed.
        collector.removeAll { $0.parent == nil }
    }

    func moveToTrash(_ node: FileNode) async {
        do {
            try await recycle(node.url)
            // If the focus was inside the deleted subtree, climb out first.
            var f = focus
            while let current = f, current === node || current.ancestors.contains(where: { $0 === node }) {
                f = node.parent
            }
            node.detach()
            collector.removeAll { $0 === node }
            if let f { setFocus(f) } else if let root { setFocus(root) }
            transition = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recycle(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard let root, query.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let needle = query.lowercased()
            var results: [FileNode] = []
            var stack = [root]
            while let node = stack.popLast(), results.count < 200 {
                if Task.isCancelled { return }
                if node.name.lowercased().contains(needle) { results.append(node) }
                stack.append(contentsOf: node.children)
            }
            let sorted = results.sorted { $0.size > $1.size }
            await MainActor.run { [weak self] in
                guard let self, self.searchQuery.trimmingCharacters(in: .whitespaces) == query else { return }
                self.searchResults = sorted
            }
        }
    }

    // MARK: - Debug hooks

    /// `--autofocus <name>` zooms into a child of the root (same path as
    /// clicking its segment); `--autotrash <name>` moves a child to the Trash
    /// (same path as the context menu); `--report <path>` writes the tree as
    /// text and exits.
    private func runDebugActions() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--autofocus"), args.count > index + 1,
           let child = root?.children.first(where: { $0.name == args[index + 1] }) {
            setFocus(child)
        }
        if let index = args.firstIndex(of: "--autotrash"), args.count > index + 1,
           let child = root?.children.first(where: { $0.name == args[index + 1] }) {
            Task { await moveToTrash(child) }
        }
        if let index = args.firstIndex(of: "--autocollect"), args.count > index + 1,
           let child = root?.children.first(where: { $0.name == args[index + 1] }) {
            toggleCollected(child)
        }
        if let index = args.firstIndex(of: "--autosearch"), args.count > index + 1 {
            searchQuery = args[index + 1]
        }
        if let index = args.firstIndex(of: "--report"), args.count > index + 1, let root {
            var lines = ["\(root.url.path)  \(root.size)  (\(formatBytes(root.size)))  skipped=\(skipped)"]
            for child in root.children.prefix(25) {
                lines.append("  \(child.name)  \(child.size)  (\(formatBytes(child.size)))")
                for grandchild in child.children.prefix(5) {
                    lines.append("    \(grandchild.name)  \(grandchild.size)  (\(formatBytes(grandchild.size)))")
                }
            }
            try? lines.joined(separator: "\n").write(
                toFile: args[index + 1], atomically: true, encoding: .utf8
            )
            exit(0)
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
