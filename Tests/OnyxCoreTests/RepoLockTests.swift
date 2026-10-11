import Foundation
import Testing
@testable import OnyxCore

struct RepoLockTests {
    @Test func lockExcludesSecondAcquirer() throws {
        let paths = tempPaths()
        let me = getpid()
        let a = RepoLock(paths: paths, repoRoot: "/r", pid: me, isAlive: { _ in true })
        let b = RepoLock(paths: paths, repoRoot: "/r", pid: me, isAlive: { _ in true })
        try a.acquire()
        #expect(throws: OnyxError.lockTimeout) { try b.acquire(timeout: 0.3, poll: 0.05) }
    }

    @Test func lockStealsFromDeadHolder() throws {
        let paths = tempPaths()
        let dead = RepoLock(paths: paths, repoRoot: "/r", pid: 999_999, isAlive: { _ in true })
        try dead.acquire()
        let b = RepoLock(paths: paths, repoRoot: "/r", pid: 42, isAlive: { $0 != 999_999 })
        try b.acquire(timeout: 0.1, poll: 0.05)
    }

    @Test func releaseAllowsReacquire() throws {
        let paths = tempPaths()
        let a = RepoLock(paths: paths, repoRoot: "/r", pid: 1, isAlive: { _ in true })
        try a.acquire()
        a.release()
        try RepoLock(paths: paths, repoRoot: "/r", pid: 2, isAlive: { _ in true }).acquire(timeout: 0.1)
    }

    @Test func differentReposDoNotBlock() throws {
        let paths = tempPaths()
        try RepoLock(paths: paths, repoRoot: "/r1", pid: 1, isAlive: { _ in true }).acquire()
        try RepoLock(paths: paths, repoRoot: "/r2", pid: 1, isAlive: { _ in true }).acquire(timeout: 0.1)
    }
}
