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

    init(withRemote: Bool = true, branch: String = "main", originHead: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let r = String(cString: realpath(root.path, nil))
        origin = r + "/origin.git"
        work = r + "/work"
        if withRemote {
            _ = try Fixture.sh("git init -q --bare -b \(branch) \(origin) && git init -q -b \(branch) \(work) && git -C \(work) remote add origin \(origin)", in: r)
        } else {
            _ = try Fixture.sh("git init -q -b \(branch) \(work)", in: r)
        }
        _ = try Fixture.sh("git config user.name t && git config user.email t@t && echo base > f.txt && git add . && git commit -qm base", in: work)
        if withRemote {
            _ = try Fixture.sh("git push -q -u origin \(branch)", in: work)
            if originHead { _ = try Fixture.sh("git remote set-head origin \(branch)", in: work) }
        }
        paths = OnyxPaths(env: ["ONYX_HOME": r + "/home"])
        registry = PaneRegistry(paths: paths, startTime: { _ in 1 })
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

    func wt(_ id8: String) -> String { "\(work)/.onyx-worktrees/\(id8)" }

    func commit(_ file: String, _ content: String, in dir: String) throws {
        try sh("git config user.name t && git config user.email t@t && printf '\(content)\\n' > \(file) && git add \(file) && git commit -qm \(file)", in: dir)
    }

    func originFiles() throws -> [String] {
        try sh("git ls-tree --name-only HEAD", in: origin).split(separator: "\n").map(String.init)
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
        let r = try b.push(dir: fx.wt("bbbbbbbb"))
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
        #expect(try a.push(dir: fx.work).exitCode == 0)
        #expect(try b.push(dir: fx.wt("bbbbbbbb")).exitCode == 0)
        #expect(Set(try fx.originFiles()) == ["a.txt", "b.txt", "f.txt"])
        // and the main pane catches up on its next push
        try fx.commit("a2.txt", "a2", in: fx.work)
        #expect(try a.push(dir: fx.work).exitCode == 0)
        #expect(Set(try fx.originFiles()) == ["a.txt", "a2.txt", "b.txt", "f.txt"])
    }

    @Test func conflictReported() throws {
        let fx = try Fixture()
        let a = try fx.pane("aaaaaaaa1"), b = try fx.pane("bbbbbbbb2")
        _ = try a.claim(dir: fx.work, task: "a")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("f.txt", "from a", in: fx.work)
        try fx.commit("f.txt", "from b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        #expect(try a.push(dir: fx.work).exitCode == 0)
        let r = try b.push(dir: fx.wt("bbbbbbbb"))
        #expect(r.exitCode == 1)
        #expect(r.output == "CONFLICT f.txt")
        // lock was released: pane A can still push
        try fx.commit("c.txt", "c", in: fx.work)
        #expect(try a.push(dir: fx.work).exitCode == 0)
    }

    @Test func noRemote() throws {
        let fx = try Fixture(withRemote: false)
        let a = try fx.pane("aaaaaaaa1")
        _ = try a.claim(dir: fx.work, task: "a")
        let r = try a.push(dir: fx.work)
        #expect(r.exitCode == 2)
        #expect(r.output == "NO_REMOTE")
    }

    @Test func pushWithoutClaimFails() throws {
        let fx = try Fixture()
        #expect(throws: OnyxError.self) { try fx.pane("aaaaaaaa1").push(dir: fx.work) }
    }

    @Test func releaseRemovesMergedWorktree() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("b.txt", "b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        _ = try b.push(dir: fx.wt("bbbbbbbb"))
        #expect(try b.release(dir: fx.wt("bbbbbbbb")) == "RELEASED removed-worktree \(fx.work)")
        #expect(!FileManager.default.fileExists(atPath: "\(fx.work)/.onyx-worktrees/bbbbbbbb"))
        #expect(try fx.sh("git branch --list onyx/bbbbbbbb", in: fx.work) == "")
        #expect(fx.registry.claim(paneId: "bbbbbbbb2", repoRoot: fx.work) == nil)
    }

    @Test func releaseKeepsUnmergedWorktree() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("b.txt", "b", in: "\(fx.work)/.onyx-worktrees/bbbbbbbb")
        #expect(try b.release(dir: fx.wt("bbbbbbbb")) == "RELEASED kept-worktree \(fx.work)/.onyx-worktrees/bbbbbbbb")
    }

    @Test func worktreeDoesNotCarryUnpushedMainCommits() throws {
        let fx = try Fixture()
        let a = try fx.pane("aaaaaaaa1"), b = try fx.pane("bbbbbbbb2")
        _ = try a.claim(dir: fx.work, task: "a")
        try fx.commit("wip.txt", "unfinished", in: fx.work)  // A's local, unpushed work
        _ = try b.claim(dir: fx.work, task: "b")
        #expect(!FileManager.default.fileExists(atPath: fx.wt("bbbbbbbb") + "/wip.txt"))
        try fx.commit("b.txt", "b", in: fx.wt("bbbbbbbb"))
        #expect(try b.push(dir: fx.wt("bbbbbbbb")).exitCode == 0)
        #expect(!(try fx.originFiles().contains("wip.txt")))
    }

    @Test func onePaneTwoReposPushesTheRepoItIsIn() throws {
        let x = try Fixture(), y = try Fixture()
        // Same ONYX_HOME for both repos so it is one pane.
        let reg = x.registry
        try reg.markAlive(paneId: "aaaaaaaa1", pid: 1)
        let a = PaneCommands(paneId: "aaaaaaaa1", registry: reg, paths: x.paths)
        _ = try a.claim(dir: x.work, task: "x")
        _ = try a.claim(dir: y.work, task: "y")
        try x.commit("x.txt", "x", in: x.work)
        #expect(try a.push(dir: x.work).exitCode == 0)
        #expect(try x.originFiles().contains("x.txt"))
        #expect(reg.claim(paneId: "aaaaaaaa1", repoRoot: x.work) != nil)
        #expect(reg.claim(paneId: "aaaaaaaa1", repoRoot: y.work) != nil)
    }

    @Test func releaseKeepsDirtyWorktree() throws {
        let fx = try Fixture()
        _ = try fx.pane("aaaaaaaa1").claim(dir: fx.work, task: "a")
        let b = try fx.pane("bbbbbbbb2")
        _ = try b.claim(dir: fx.work, task: "b")
        try "draft\n".write(toFile: fx.wt("bbbbbbbb") + "/draft.txt", atomically: true, encoding: .utf8)
        #expect(try b.release(dir: fx.wt("bbbbbbbb")) == "RELEASED kept-worktree \(fx.wt("bbbbbbbb")) dirty")
        #expect(FileManager.default.fileExists(atPath: fx.wt("bbbbbbbb") + "/draft.txt"))
    }

    @Test func autostashConflictIsReported() throws {
        let fx = try Fixture()
        let a = try fx.pane("aaaaaaaa1"), b = try fx.pane("bbbbbbbb2")
        _ = try a.claim(dir: fx.work, task: "a")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("f.txt", "from a", in: fx.work)
        #expect(try a.push(dir: fx.work).exitCode == 0)
        try fx.commit("b.txt", "b", in: fx.wt("bbbbbbbb"))
        try "from b uncommitted\n".write(toFile: fx.wt("bbbbbbbb") + "/f.txt", atomically: true, encoding: .utf8)
        let r = try b.push(dir: fx.wt("bbbbbbbb"))
        #expect(r.exitCode == 0)
        #expect(r.output.hasPrefix("PUSHED ") && r.output.hasSuffix(" STASHED"))
    }

    @Test func detachedHeadIsRefused() throws {
        let fx = try Fixture()
        let a = try fx.pane("aaaaaaaa1")
        _ = try a.claim(dir: fx.work, task: "a")
        try fx.sh("git checkout -q --detach", in: fx.work)
        #expect(throws: OnyxError.self) { try a.push(dir: fx.work) }
        #expect(!(try fx.sh("git ls-remote --heads origin", in: fx.work).contains("refs/heads/HEAD")))
    }

    @Test func masterDefaultWithoutOriginHead() throws {
        let fx = try Fixture(branch: "master", originHead: false)
        let a = try fx.pane("aaaaaaaa1"), b = try fx.pane("bbbbbbbb2")
        _ = try a.claim(dir: fx.work, task: "a")
        _ = try b.claim(dir: fx.work, task: "b")
        try fx.commit("b.txt", "b", in: fx.wt("bbbbbbbb"))
        #expect(try b.push(dir: fx.wt("bbbbbbbb")).exitCode == 0)
        #expect(try fx.sh("git ls-tree --name-only master", in: fx.origin).contains("b.txt"))
    }
}
