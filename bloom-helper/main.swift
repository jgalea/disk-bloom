import BloomCore
import Foundation

// Privileged scan daemon, registered via SMAppService and launched on demand
// by launchd when the app connects to its Mach service. Runs as root, so
// admin scans need no per-scan password prompt.

final class HelperService: NSObject, BloomHelperProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var currentProgress: ScanProgress?

    func startScan(path: String, output: FileHandle, reply: @escaping (String?) -> Void) {
        let progress = ScanProgress()
        lock.lock()
        currentProgress = progress
        lock.unlock()

        // XPC hands these in on its own queue; the scan task is their only user.
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let reply = reply
        Task.detached(priority: .userInitiated) {
            let tree = await DiskScanner.scan(url: URL(fileURLWithPath: path), progress: progress)
            do {
                try TreeSerializer.write(root: tree, skipped: progress.snapshot.skipped, to: output)
                try output.close()
                reply(nil)
            } catch {
                reply(String(describing: error))
            }
        }
    }

    func progress(reply: @escaping (Int, Int64, Int) -> Void) {
        lock.lock()
        let snapshot = currentProgress?.snapshot ?? ScanSnapshot()
        lock.unlock()
        reply(snapshot.items, snapshot.bytes, snapshot.skipped)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(BloomHelper.codeSigningRequirement)
        connection.exportedInterface = NSXPCInterface(with: BloomHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: BloomHelper.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
