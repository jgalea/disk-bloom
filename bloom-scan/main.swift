import BloomCore
import Foundation

// Privileged scan helper, embedded in Bloom.app and launched by the app via
// an administrator-privileges prompt (DaisyDisk-style "admin scan").
//
//   bloom-scan <path> <output-tree-file> [--progress <file>]
//
// Scans <path> with the same engine as the app, writes the serialized tree to
// <output-tree-file>, and (optionally) rewrites <file> with
// "items bytes skipped" twice a second so the app can show live progress.

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: bloom-scan <path> <out> [--progress <file>]\n".utf8))
    exit(64)
}
let targetPath = args[1]
let outputPath = args[2]
var progressPath: String?
if let index = args.firstIndex(of: "--progress"), args.count > index + 1 {
    progressPath = args[index + 1]
}

let progress = ScanProgress()

let reporter: Task<Void, Never>? = progressPath.map { path in
    Task.detached {
        while !Task.isCancelled {
            let snap = progress.snapshot
            try? "\(snap.items) \(snap.bytes) \(snap.skipped)"
                .write(toFile: path, atomically: true, encoding: .utf8)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    let tree = await DiskScanner.scan(url: URL(fileURLWithPath: targetPath), progress: progress)
    reporter?.cancel()
    do {
        try TreeSerializer.write(root: tree, skipped: progress.snapshot.skipped, to: URL(fileURLWithPath: outputPath))
    } catch {
        FileHandle.standardError.write(Data("bloom-scan: \(error)\n".utf8))
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
exit(0)
