import CryptoKit
import Foundation

/// Cross-process per-repo lock: an atomic `mkdir` of `locks/<hash>` holding the owner's pid.
/// A lock whose owner is dead is stolen.
public struct RepoLock: Sendable {
    let dir: URL
    let pid: Int32
    let isAlive: @Sendable (Int32) -> Bool

    public init(paths: OnyxPaths, repoRoot: String, pid: Int32 = getpid(),
                isAlive: @escaping @Sendable (Int32) -> Bool = isProcessAlive) {
        let digest = SHA256.hash(data: Data(repoRoot.utf8)).map { String(format: "%02x", $0) }.joined()
        dir = paths.locks.appendingPathComponent(String(digest.prefix(16)))
        self.pid = pid
        self.isAlive = isAlive
    }

    private var pidFile: URL { dir.appendingPathComponent("pid") }

    public func acquire(timeout: TimeInterval = 300, poll: TimeInterval = 0.2) throws {
        try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if mkdir(dir.path, 0o755) == 0 {
                try String(pid).write(to: pidFile, atomically: true, encoding: .utf8)
                return
            }
            let holder = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0) }
            // No pid yet means the holder is between mkdir and write; give it a moment.
            if let holder, !isAlive(holder) {
                try? FileManager.default.removeItem(at: dir)
                continue
            }
            if Date() >= deadline { throw OnyxError.lockTimeout }
            Thread.sleep(forTimeInterval: poll)
        }
    }

    public func release() {
        try? FileManager.default.removeItem(at: dir)
    }
}
