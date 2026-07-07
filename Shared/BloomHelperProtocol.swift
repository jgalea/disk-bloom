import Foundation

/// XPC interface between the app and the privileged bloom-helper daemon.
/// Compiled into both targets; selectors must stay in sync.
@objc(BloomHelperProtocol)
protocol BloomHelperProtocol {
    /// Scan `path` as root and stream the serialized tree into `output`
    /// (a file handle the app owns, passed as a file descriptor over XPC).
    /// Replies with nil on success or an error description.
    func startScan(path: String, output: FileHandle, reply: @escaping (String?) -> Void)

    /// Snapshot of the scan in flight: items, bytes, skipped.
    func progress(reply: @escaping (Int, Int64, Int) -> Void)
}

enum BloomHelper {
    static let machServiceName = "com.jeangalea.bloom.helper"
    static let plistName = "com.jeangalea.bloom.helper.plist"
    /// Only same-team binaries may talk to the root daemon.
    static let codeSigningRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "V39FW47X6K""#
}
