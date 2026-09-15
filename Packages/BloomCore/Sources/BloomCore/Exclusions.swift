import Foundation

/// Absolute paths the scanner refuses to descend into.
///
/// An excluded tree is never opened, so its contents cost nothing to skip and
/// contribute nothing to any parent's size. That is the point: a
/// `--link-dest` snapshot farm or a cache you have already decided about
/// should not dominate the chart every time you scan.
public struct Exclusions: Sendable, Equatable {
    public static let none = Exclusions(paths: [])

    private let paths: Set<String>

    public init(paths: [String]) {
        self.paths = Set(paths.compactMap(Exclusions.normalize))
    }

    public var isEmpty: Bool { paths.isEmpty }

    public var sortedPaths: [String] { paths.sorted() }

    /// True when `path` is excluded outright or sits under something excluded.
    public func excludes(_ path: String) -> Bool {
        guard let candidate = Exclusions.normalize(path) else { return false }
        if paths.contains(candidate) { return true }
        return paths.contains { candidate.hasPrefix($0 + "/") }
    }

    /// Absolute, symlink-free-ish, no trailing slash. Returns nil for input
    /// that could never match a scanned path.
    public static func normalize(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        let standardized = (expanded as NSString).standardizingPath
        guard standardized != "/" else { return nil }
        return standardized
    }
}
