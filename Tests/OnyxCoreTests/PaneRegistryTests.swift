import Foundation
import Testing
@testable import OnyxCore

struct PaneRegistryTests {
    @Test func liveReturnsOnlyAlivePanes() throws {
        let paths = tempPaths()
        let reg = PaneRegistry(paths: paths, startTime: { $0 == 1 ? 10 : nil })
        try reg.markAlive(paneId: "a", pid: 1)
        try reg.markAlive(paneId: "b", pid: 2)
        try reg.save(claim("a"))
        try reg.save(claim("b"))
        #expect(reg.live().map(\.paneId) == ["a"])
        let left = try FileManager.default.contentsOfDirectory(atPath: paths.panes.path).sorted()
        #expect(left.count == 2 && left.contains("a.pid"))
    }

    @Test func claimWithoutPidFileIsDead() throws {
        let reg = PaneRegistry(paths: tempPaths(), startTime: { _ in 10 })
        try reg.save(claim("ghost"))
        #expect(reg.live().isEmpty)
    }

    @Test func markClosedRemovesBothFiles() throws {
        let paths = tempPaths()
        let reg = PaneRegistry(paths: paths, startTime: { _ in 10 })
        try reg.markAlive(paneId: "a", pid: 1)
        try reg.save(claim("a"))
        reg.markClosed(paneId: "a")
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.panes.path).isEmpty)
    }

    @Test func reusedPidIsDead() throws {
        final class Clock: @unchecked Sendable { var start: UInt64 = 100 }
        let clock = Clock()
        let reg = PaneRegistry(paths: tempPaths(), startTime: { _ in clock.start })
        try reg.markAlive(paneId: "a", pid: 7)
        try reg.save(claim("a"))
        #expect(reg.live().count == 1)
        clock.start = 200  // pid 7 now belongs to some other process
        #expect(reg.live().isEmpty)
    }

    @Test func pidZeroIsNeverAlive() {
        #expect(!isProcessAlive(0))
        #expect(!isProcessAlive(-1))
    }

    @Test func claimsAreKeptPerRepo() throws {
        let reg = PaneRegistry(paths: tempPaths(), startTime: { _ in 10 })
        try reg.markAlive(paneId: "a", pid: 1)
        try reg.save(claim("a", repo: "/x"))
        try reg.save(claim("a", repo: "/y"))
        #expect(Set(reg.live().map(\.repoRoot)) == ["/x", "/y"])
        reg.remove(paneId: "a", repoRoot: "/x")
        #expect(reg.live().map(\.repoRoot) == ["/y"])
    }

    @Test func pathsDefaultToApplicationSupport() {
        let p = OnyxPaths(env: ["HOME": "/Users/x"])
        #expect(p.home.path == "/Users/x/Library/Application Support/Onyx")
        #expect(p.prompt.lastPathComponent == "pane-prompt.md")
    }
}
