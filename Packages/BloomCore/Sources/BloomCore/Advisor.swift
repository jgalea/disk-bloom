import Foundation

/// What a chart wedge actually is, and the right way to get the space back.
///
/// A visualizer can only say "this is 74 GB". For tool-owned directories that
/// is the wrong unit of decision: selecting and trashing a Docker disk image
/// or a simulator runtime either does nothing useful or breaks the tool. The
/// reclaim step for those is a command, not a delete.
public struct Advice: Sendable, Equatable, Identifiable {
    /// How much thought is owed before reclaiming.
    public enum Safety: String, Sendable {
        /// Rebuilt automatically on next use. Cost of deleting is time.
        case regenerable
        /// May hold the only copy of something. Look before reclaiming.
        case review
        /// macOS reclaims this on its own under disk pressure.
        case systemManaged
    }

    public let id: String
    public let owner: String
    public let summary: String
    public let safety: Safety
    /// The correct reclaim step, when it is a command rather than a delete.
    public let command: String?

    public init(id: String, owner: String, summary: String, safety: Safety, command: String? = nil) {
        self.id = id
        self.owner = owner
        self.summary = summary
        self.safety = safety
        self.command = command
    }
}

public enum Advisor {
    /// Advice for an absolute path, or nil when nothing is known about it.
    public static func advice(for path: String) -> Advice? {
        guard let normalized = Exclusions.normalize(path) else { return nil }
        let name = (normalized as NSString).lastPathComponent

        if let match = exactRules.first(where: { normalized == expand($0.path) }) {
            return match.advice
        }
        if let match = prefixRules.first(where: { normalized.hasPrefix(expand($0.path)) }) {
            return match.advice
        }
        return namedRules.first { $0.name == name }?.advice
    }

    /// Advice for every node in a tree that has some, largest first. Only the
    /// outermost match is reported: once DerivedData is named, its children
    /// are noise.
    public static func advise(tree: FileNode, minimumBytes: Int64 = 100 << 20) -> [(node: FileNode, advice: Advice)] {
        var found: [(node: FileNode, advice: Advice)] = []
        var stack = [tree]
        while let node = stack.popLast() {
            guard node.size >= minimumBytes else { continue }
            if let advice = advice(for: node.path) {
                found.append((node, advice))
                continue // don't descend into something already named
            }
            stack.append(contentsOf: node.children)
        }
        return found.sorted { $0.node.size > $1.node.size }
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private struct Rule {
        let path: String
        let advice: Advice
    }

    private struct NamedRule {
        let name: String
        let advice: Advice
    }

    // MARK: - Rules

    private static let exactRules: [Rule] = [
        Rule(path: "~/Library/Developer/Xcode/DerivedData", advice: Advice(
            id: "xcode.deriveddata",
            owner: "Xcode",
            summary: "Build intermediates and indexes. Xcode rebuilds them on the next build; the only cost of deleting is a slow first build.",
            safety: .regenerable,
            command: "rm -rf ~/Library/Developer/Xcode/DerivedData/*"
        )),
        Rule(path: "~/Library/Developer/Xcode/iOS DeviceSupport", advice: Advice(
            id: "xcode.devicesupport",
            owner: "Xcode",
            summary: "Debug symbols copied off every iOS device and version you have attached. Re-copied on next attach, which takes a few minutes.",
            safety: .regenerable,
            command: "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/*"
        )),
        Rule(path: "~/Library/Developer/Xcode/Archives", advice: Advice(
            id: "xcode.archives",
            owner: "Xcode",
            summary: "Shipped-build archives holding the dSYMs that symbolicate crash reports from those builds. Deleting an archive for a released version loses that ability for good.",
            safety: .review
        )),
        Rule(path: "~/Library/Developer/CoreSimulator", advice: Advice(
            id: "xcode.coresimulator",
            owner: "Xcode Simulator",
            summary: "Simulator devices and downloaded runtimes. Devices for runtimes you no longer have installed are pure waste.",
            safety: .regenerable,
            command: "xcrun simctl delete unavailable"
        )),
        Rule(path: "~/Library/Caches/Homebrew", advice: Advice(
            id: "homebrew.cache",
            owner: "Homebrew",
            summary: "Downloaded bottles and source tarballs kept after installing.",
            safety: .regenerable,
            command: "brew cleanup -s"
        )),
        Rule(path: "~/.npm", advice: Advice(
            id: "npm.cache",
            owner: "npm",
            summary: "Package tarball cache. npm re-downloads what it needs; the cache is an offline and speed optimization, never a source of truth.",
            safety: .regenerable,
            command: "npm cache clean --force"
        )),
        Rule(path: "~/Library/Application Support/MobileSync/Backup", advice: Advice(
            id: "ios.backups",
            owner: "Finder device backup",
            summary: "Local iPhone and iPad backups. For a device that is lost, wiped, or no longer yours, this may be the only copy of its data.",
            safety: .review
        )),
        Rule(path: "~/.Trash", advice: Advice(
            id: "system.trash",
            owner: "Finder",
            summary: "Files already marked for deletion but still occupying disk.",
            safety: .review,
            command: "osascript -e 'tell application \"Finder\" to empty trash'"
        )),
    ]

    private static let prefixRules: [Rule] = [
        Rule(path: "~/Library/Group Containers/HUAQ24HBR6.dev.orbstack", advice: Advice(
            id: "orbstack.vm",
            owner: "OrbStack",
            summary: "A sparse VM disk image. The chart cannot see inside it, so images, build cache, volumes, and stopped containers all read as one opaque blob. Reclaiming happens through Docker, not by deleting the file. Adding --volumes also destroys database volumes, so check what is in them first.",
            safety: .review,
            command: "docker system df   # then: docker builder prune -af && docker image prune -a"
        )),
        Rule(path: "~/Library/Containers/com.docker.docker", advice: Advice(
            id: "docker.desktop",
            owner: "Docker Desktop",
            summary: "Docker's VM disk image. Same story as OrbStack: reclaim through Docker, not by deleting the file.",
            safety: .review,
            command: "docker system df   # then: docker builder prune -af && docker image prune -a"
        )),
        Rule(path: "~/.cargo/registry", advice: Advice(
            id: "cargo.registry",
            owner: "Cargo",
            summary: "Downloaded crate sources and their extracted copies. Re-fetched on demand.",
            safety: .regenerable
        )),
        Rule(path: "~/.gradle/caches", advice: Advice(
            id: "gradle.cache",
            owner: "Gradle",
            summary: "Downloaded dependencies and build caches. Re-fetched on the next build.",
            safety: .regenerable
        )),
        Rule(path: "~/Library/Caches", advice: Advice(
            id: "user.caches",
            owner: "Mixed, one folder per app",
            summary: "Not one thing. Most subfolders regenerate, but some apps keep real state here. Open it and judge per app rather than emptying the lot.",
            safety: .review
        )),
        Rule(path: "/Library/Caches", advice: Advice(
            id: "system.caches",
            owner: "Mixed, system-wide",
            summary: "System-wide equivalent of the user cache folder. Judge per app.",
            safety: .review
        )),
        Rule(path: "/System/Volumes/Data/.Spotlight-V100", advice: Advice(
            id: "system.spotlight",
            owner: "Spotlight",
            summary: "The search index. Deleting it forces a full reindex that costs hours of CPU and saves nothing lasting.",
            safety: .systemManaged
        )),
    ]

    /// Directories recognized by name wherever they appear.
    private static let namedRules: [NamedRule] = [
        NamedRule(name: "node_modules", advice: Advice(
            id: "node.modules",
            owner: "npm / yarn / pnpm",
            summary: "Installed dependencies for one project, reproducible from its lockfile.",
            safety: .regenerable,
            command: "npm ci   # in the project directory, to restore"
        )),
        NamedRule(name: ".build", advice: Advice(
            id: "swiftpm.build",
            owner: "Swift Package Manager",
            summary: "Build products and checked-out dependencies for one package.",
            safety: .regenerable,
            command: "swift package clean"
        )),
        NamedRule(name: "DerivedData", advice: Advice(
            id: "xcode.deriveddata.local",
            owner: "Xcode",
            summary: "Per-project build intermediates. Rebuilt on the next build.",
            safety: .regenerable
        )),
        NamedRule(name: "__pycache__", advice: Advice(
            id: "python.pycache",
            owner: "Python",
            summary: "Compiled bytecode, regenerated on the next import.",
            safety: .regenerable
        )),
    ]
}
