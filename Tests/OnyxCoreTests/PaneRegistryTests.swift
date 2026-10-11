import Foundation
import Testing
@testable import OnyxCore

struct PaneRegistryTests {
    @Test func liveReturnsOnlyAlivePanes() throws {
        let paths = tempPaths()
        let reg = PaneRegistry(paths: paths, isAlive: { $0 == 1 })
        try reg.markAlive(paneId: "a", pid: 1)
        try reg.markAlive(paneId: "b", pid: 2)
        try reg.save(claim("a"))
        try reg.save(claim("b"))
        #expect(reg.live().map(\.paneId) == ["a"])
        let left = try FileManager.default.contentsOfDirectory(atPath: paths.panes.path).sorted()
        #expect(left == ["a.json", "a.pid"])
    }

    @Test func claimWithoutPidFileIsDead() throws {
        let reg = PaneRegistry(paths: tempPaths(), isAlive: { _ in true })
        try reg.save(claim("ghost"))
        #expect(reg.live().isEmpty)
    }

    @Test func markClosedRemovesBothFiles() throws {
        let paths = tempPaths()
        let reg = PaneRegistry(paths: paths, isAlive: { _ in true })
        try reg.markAlive(paneId: "a", pid: 1)
        try reg.save(claim("a"))
        reg.markClosed(paneId: "a")
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.panes.path).isEmpty)
    }

    @Test func pathsDefaultToApplicationSupport() {
        let p = OnyxPaths(env: ["HOME": "/Users/x"])
        #expect(p.home.path == "/Users/x/Library/Application Support/Onyx")
        #expect(p.prompt.lastPathComponent == "pane-prompt.md")
    }
}
