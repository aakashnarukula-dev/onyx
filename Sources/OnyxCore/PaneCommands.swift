import Foundation

/// The `onyx-pane` subcommands. Each returns the single line the CLI prints.
public struct PaneCommands {
    let paneId: String
    let registry: PaneRegistry
    let paths: OnyxPaths

    public init(paneId: String, registry: PaneRegistry, paths: OnyxPaths) {
        self.paneId = paneId
        self.registry = registry
        self.paths = paths
    }

    var shortId: String { String(paneId.prefix(8)) }

    /// The main checkout of the repo containing `dir`, even when `dir` is inside a worktree.
    func repoRoot(of dir: String) throws -> String {
        guard let common = try? Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: dir) else {
            throw OnyxError.notARepo(dir)
        }
        let url = URL(fileURLWithPath: common)
        if url.lastPathComponent == ".git" { return url.deletingLastPathComponent().path }
        // A worktree-less layout (e.g. bare repo) has no main checkout to claim.
        throw OnyxError.notARepo(dir)
    }

    public func claim(dir: String, task: String) throws -> String {
        let root = try repoRoot(of: dir)
        let live = registry.live()
        if var mine = live.first(where: { $0.paneId == paneId && $0.repoRoot == root }) {
            mine.task = task
            mine.updatedAt = Date()
            try registry.save(mine)
            return line(for: mine)
        }
        let mainTaken = live.contains { $0.paneId != paneId && $0.repoRoot == root && $0.worktree == nil }
        var c = PaneClaim(paneId: paneId, repoRoot: root, worktree: nil, branch: "", task: task, updatedAt: Date())
        if mainTaken {
            let path = "\(root)/.onyx-worktrees/\(shortId)"
            let branch = "onyx/\(shortId)"
            try excludeWorktreeDir(root: root)
            if !FileManager.default.fileExists(atPath: path) {
                let exists = Git.result(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], in: root).status == 0
                try Git.run(exists ? ["worktree", "add", path, branch] : ["worktree", "add", "-b", branch, path, "HEAD"], in: root)
            }
            c.worktree = path
            c.branch = branch
        } else {
            c.branch = (try? Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)) ?? "HEAD"
        }
        try registry.save(c)
        return line(for: c)
    }

    private func line(for c: PaneClaim) -> String {
        if let wt = c.worktree { return "USE_WORKTREE \(wt) \(c.branch)" }
        return "OK \(c.repoRoot)"
    }

    private func excludeWorktreeDir(root: String) throws {
        let gitDir = try Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: root)
        let info = URL(fileURLWithPath: gitDir).appendingPathComponent("info")
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let file = info.appendingPathComponent("exclude")
        let current = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard !current.split(separator: "\n").contains(".onyx-worktrees/") else { return }
        let sep = current.isEmpty || current.hasSuffix("\n") ? "" : "\n"
        try (current + sep + ".onyx-worktrees/\n").write(to: file, atomically: true, encoding: .utf8)
    }

    public func who(dir: String) throws -> String {
        let root = try repoRoot(of: dir)
        return registry.live().filter { $0.repoRoot == root }.map {
            "\($0.paneId.prefix(8)) \($0.branch) \($0.worktree ?? "main") \($0.task)"
        }.joined(separator: "\n")
    }

    private func myClaim() throws -> PaneClaim {
        guard let c = registry.claim(paneId: paneId) else {
            throw OnyxError.git("this pane has no claim; run `onyx-pane claim <dir> \"<task>\"` first")
        }
        return c
    }

    /// The remote's default branch (origin/HEAD), else `main`.
    private func defaultBranch(root: String) -> String {
        if let ref = try? Git.run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: root),
           ref.hasPrefix("origin/") {
            return String(ref.dropFirst("origin/".count))
        }
        return "main"
    }

    private func hasOrigin(_ root: String) -> Bool {
        ((try? Git.run(["remote"], in: root)) ?? "").split(separator: "\n").contains("origin")
    }

    public func push() throws -> (output: String, exitCode: Int32) {
        let c = try myClaim()
        let checkout = c.worktree ?? c.repoRoot
        let lock = RepoLock(paths: paths, repoRoot: c.repoRoot)
        try lock.acquire()
        defer { lock.release() }

        guard hasOrigin(c.repoRoot) else { return ("NO_REMOTE", 2) }
        let target = defaultBranch(root: c.repoRoot)
        try Git.run(["fetch", "-q", "origin"], in: checkout)

        let branch = c.worktree == nil ? try Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: checkout) : target
        let upstream = Git.result(["rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(branch)"], in: checkout).status == 0
            ? "origin/\(branch)" : "origin/\(target)"

        let rebase = Git.result(["rebase", "--autostash", upstream], in: checkout)
        if rebase.status != 0 {
            let files = (try? Git.run(["diff", "--name-only", "--diff-filter=U"], in: checkout)) ?? ""
            if files.isEmpty { throw OnyxError.git(rebase.err.isEmpty ? rebase.out : rebase.err) }
            return ("CONFLICT " + files.split(separator: "\n").joined(separator: " "), 1)
        }
        try Git.run(["push", "-q", "origin", "HEAD:refs/heads/\(branch)"], in: checkout)
        let sha = try Git.run(["rev-parse", "--short", "HEAD"], in: checkout)
        return ("PUSHED \(sha)", 0)
    }

    public func release() throws -> String {
        let c = try myClaim()
        registry.remove(paneId: paneId)
        guard let wt = c.worktree else { return "RELEASED" }
        let root = c.repoRoot
        let target = defaultBranch(root: root)
        var base = target
        if hasOrigin(root) {
            _ = Git.result(["fetch", "-q", "origin"], in: root)
            base = "origin/\(target)"
        }
        let merged = Git.result(["merge-base", "--is-ancestor", c.branch, base], in: root).status == 0
        guard merged else { return "RELEASED kept-worktree \(wt)" }
        try Git.run(["worktree", "remove", "--force", wt], in: root)
        try Git.run(["branch", "-D", c.branch], in: root)
        return "RELEASED removed-worktree"
    }
}
