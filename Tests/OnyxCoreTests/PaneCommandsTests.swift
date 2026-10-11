import Foundation
import Testing
@testable import OnyxCore

/// A bare `origin` plus one clone (`work`) with a seeded `f.txt` on main.
struct Fixture {
    let root: URL
    let origin: String
    let work: String
    let paths: OnyxPaths
    let registry: PaneRegistry

    init(withRemote: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let r = String(cString: realpath(root.path, nil))
        origin = r + "/origin.git"
        work = r + "/work"
        if withRemote {
            _ = try Fixture.sh("git init -q --bare -b main \(origin) && git clone -q \(origin) \(work)", in: r)
        } else {
            _ = try Fixture.sh("git init -q -b main \(work)", in: r)
        }
        _ = try Fixture.sh("git config user.name t && git config user.email t@t && echo base > f.txt && git add . && git commit -qm base", in: work)
        if withRemote { _ = try Fixture.sh("git push -q origin main", in: work) }
        paths = OnyxPaths(env: ["ONYX_HOME": r + "/home"])
        registry = PaneRegistry(paths: paths, isAlive: { _ in true })
    }

    func pane(_ id: String) throws -> PaneCommands {
        try registry.markAlive(paneId: id, pid: 1)
        return PaneCommands(paneId: id, registry: registry, paths: paths)
    }

    @discardableResult
    static func sh(_ cmd: String, in dir: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self)
        if p.terminationStatus != 0 { throw OnyxError.git("\(cmd): \(s)") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func sh(_ cmd: String, in dir: String) throws -> String { try Fixture.sh(cmd, in: dir) }

    func commit(_ file: String, _ content: String, in dir: String) throws {
        try sh("git config user.name t && git config user.email t@t && printf '\(content)\\n' > \(file) && git add \(file) && git commit -qm \(file)", in: dir)
    }

    func originFiles() throws -> [String] {
        try sh("git ls-tree --name-only main", in: origin).split(separator: "\n").map(String.init)
    }
}

struct PaneCommandsTests {
    @Test func firstClaimOK() throws {
        let fx = try Fixture()
        let out = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "first")
        #expect(out == "OK \(fx.work)")
    }

    @Test func secondClaimGetsWorktree() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let out = try fx.pane("bbbbbbbb2").claim(dir: fx.work, task: "b")
        let wt = "\(fx.work)/.onyx-worktrees/bbbbbbbb"
        #expect(out == "USE_WORKTREE \(wt) onyx/bbbbbbbb")
        #expect(FileManager.default.fileExists(atPath: wt + "/f.txt"))
        #expect(try fx.sh("git branch --list onyx/bbbbbbbb", in: fx.work).contains("onyx/bbbbbbbb"))
        #expect(try String(contentsOfFile: fx.work + "/.git/info/exclude", encoding: .utf8).contains(".onyx-worktrees/"))
        #expect(try fx.sh("git status --porcelain", in: fx.work) == "")
    }

    @Test func claimFromInsideWorktreeKeepsIt() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        let first = try b.claim(dir: fx.work, task: "b")
        let again = try b.claim(dir: "\(fx.work)/.onyx-worktrees/bbbbbbbb", task: "b2")
        #expect(first == again)
    }

    @Test func whoListsPanes() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "fix header")
        _ = try fx.pane("bbbbbbbb2").claim(dir: fx.work, task: "add footer")
        let out = try fx.pane("aaaaaaaa1").who(dir: fx.work)
        #expect(out == "aaaaaaaa main main fix header\nbbbbbbbb onyx/bbbbbbbb \(fx.work)/.onyx-worktrees/bbbbbbbb add footer")
    }

    @Test func worktreePushLandsOnMain() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("b.txt", "b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        let r = try b.push()
        #expect(r.exitCode == 0)
        #expect(r.output.hasPrefix("PUSHED "))
        #expect(try fx.originFiles().contains("b.txt"))
    }

    @Test func bothPanesPushNonConflicting() throws {
        let fx = try Fixture()
        let a = try fx.pane("aaaaaaaa1"), b = try fx.pane("bbbbbbbb2")
        _ = try a.claim(dir: fx.work, task: "a")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("a.txt", "a", in: fx.work)
        try fx.commit("b.txt", "b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        #expect(try a.push().exitCode == 0)
        #expect(try b.push().exitCode == 0)
        #expect(Set(try fx.originFiles()) == ["a.txt", "b.txt", "f.txt"])
        // and the main pane catches up on its next push
        try fx.commit("a2.txt", "a2", in: fx.work)
        #expect(try a.push().exitCode == 0)
        #expect(Set(try fx.originFiles()) == ["a.txt", "a2.txt", "b.txt", "f.txt"])
    }

    @Test func conflictReported() throws {
        let fx = try Fixture()
        let a = try fx.pane("aaaaaaaa1"), b = try fx.pane("bbbbbbbb2")
        _ = try a.claim(dir: fx.work, task: "a")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("f.txt", "from a", in: fx.work)
        try fx.commit("f.txt", "from b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        #expect(try a.push().exitCode == 0)
        let r = try b.push()
        #expect(r.exitCode == 1)
        #expect(r.output == "CONFLICT f.txt")
        // lock was released: pane A can still push
        try fx.commit("c.txt", "c", in: fx.work)
        #expect(try a.push().exitCode == 0)
    }

    @Test func noRemote() throws {
        let fx = try Fixture(withRemote: false)
        let a = try fx.pane("aaaaaaaa1")
        _ = try a.claim(dir: fx.work, task: "a")
        let r = try a.push()
        #expect(r.exitCode == 2)
        #expect(r.output == "NO_REMOTE")
    }

    @Test func pushWithoutClaimFails() throws {
        let fx = try Fixture()
        #expect(throws: OnyxError.self) { try fx.pane("aaaaaaaa1").push() }
    }

    @Test func releaseRemovesMergedWorktree() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("b.txt", "b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        _ = try b.push()
        #expect(try b.release() == "RELEASED removed-worktree")
        #expect(!FileManager.default.fileExists(atPath: "\(fx.work)/.onyx-worktrees/bbbbbbbb"))
        #expect(try fx.sh("git branch --list onyx/bbbbbbbb", in: fx.work) == "")
        #expect(fx.registry.claim(paneId: "bbbbbbbb2") == nil)
    }

    @Test func releaseKeepsUnmergedWorktree() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("b.txt", "b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        #expect(try b.release() == "RELEASED kept-worktree \(fx.work)/.onyx-worktrees/bbbbbbbb")
    }
}
