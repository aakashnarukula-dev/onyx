import Foundation
import Testing
@testable import OnyxCore

struct RepoLockTests {
    @Test func lockExcludesSecondAcquirer() throws {
        let paths = tempPaths()
        let a = RepoLock(paths: paths, repoRoot: "/r")
        let b = RepoLock(paths: paths, repoRoot: "/r")
        try a.acquire()
        #expect(throws: OnyxError.lockTimeout) { try b.acquire(timeout: 0.3, poll: 0.05) }
    }

    @Test func killedHolderReleasesLock() throws {
        let paths = tempPaths()
        let a = RepoLock(paths: paths, repoRoot: "/r")
        try a.acquire()
        let file = a.file.path
        a.release()
        // A separate process takes the lock and is SIGKILLed while holding it.
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        holder.arguments = ["-e", "use Fcntl ':flock'; open(F, '>>', $ARGV[0]) or die; flock(F, LOCK_EX) or die; print STDOUT \"locked\\n\"; $|=1; sleep 30", file]
        let out = Pipe()
        holder.standardOutput = out
        try holder.run()
        _ = out.fileHandleForReading.availableData  // wait for "locked"
        let b = RepoLock(paths: paths, repoRoot: "/r")
        #expect(throws: OnyxError.lockTimeout) { try b.acquire(timeout: 0.2, poll: 0.05) }
        kill(holder.processIdentifier, SIGKILL)
        holder.waitUntilExit()
        try b.acquire(timeout: 1, poll: 0.05)
    }

    @Test func releaseAllowsReacquire() throws {
        let paths = tempPaths()
        let a = RepoLock(paths: paths, repoRoot: "/r")
        try a.acquire()
        a.release()
        try RepoLock(paths: paths, repoRoot: "/r").acquire(timeout: 0.1)
    }

    @Test func differentReposDoNotBlock() throws {
        let paths = tempPaths()
        let a = RepoLock(paths: paths, repoRoot: "/r1")
        try a.acquire()
        try RepoLock(paths: paths, repoRoot: "/r2").acquire(timeout: 0.1)
    }
}
