import Foundation

/// Cross-process per-repo lock: `flock` on `locks/<repoKey>.lock`. The kernel drops it when the
/// holder exits or is killed, so a crashed push can never wedge the repo.
public final class RepoLock: @unchecked Sendable {
    public let file: URL
    private var fd: Int32 = -1

    public init(paths: OnyxPaths, repoRoot: String) {
        file = paths.locks.appendingPathComponent("\(repoKey(repoRoot)).lock")
    }

    deinit { release() }

    public func acquire(timeout: TimeInterval = 90, poll: TimeInterval = 0.2) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fd < 0 { fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644) }
        guard fd >= 0 else { throw OnyxError.git("cannot open lock \(file.path)") }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if Date() >= deadline { throw OnyxError.lockTimeout }
            Thread.sleep(forTimeInterval: poll)
        }
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }
}
