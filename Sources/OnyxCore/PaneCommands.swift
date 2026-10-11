import Foundation

/// The `onyx-pane` subcommands. Each returns the single line the CLI prints.
/// `dir` is where the command runs (the CLI passes its cwd); it selects the repo.
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
        // Serialize claims per repo so two panes claiming at once cannot both get the main checkout.
        let lock = RepoLock(paths: paths, repoRoot: root)
        try lock.acquire()
        defer { lock.release() }

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
                try Git.run(exists ? ["worktree", "add", path, branch]
                                   : ["worktree", "add", "-b", branch, path, worktreeBase(root: root)], in: root)
            }
            c.worktree = path
            c.branch = branch
        } else {
            c.branch = (try? Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)) ?? "HEAD"
        }
        try registry.save(c)
        return line(for: c)
    }

    /// Where a new worktree starts: the remote's default branch, never the main checkout's HEAD,
    /// which may hold another pane's unpushed commits.
    private func worktreeBase(root: String) throws -> String {
        let target = defaultBranch(root: root)
        if hasOrigin(root) {
            try Git.run(["fetch", "-q", "origin"], in: root)
            if Git.result(["rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(target)"], in: root).status == 0 {
                return "origin/\(target)"
            }
        }
        if Git.result(["rev-parse", "--verify", "--quiet", "refs/heads/\(target)"], in: root).status == 0 { return target }
        return "HEAD"
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

    private func myClaim(dir: String) throws -> PaneClaim {
        let root = try repoRoot(of: dir)
        guard let c = registry.claim(paneId: paneId, repoRoot: root) else {
            throw OnyxError.git("this pane has no claim on \(root); run `onyx-pane claim <dir> \"<task>\"` first")
        }
        return c
    }

    /// The remote's default branch: origin/HEAD, else what the remote reports, else `main`.
    private func defaultBranch(root: String) -> String {
        if let ref = try? Git.run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: root),
           ref.hasPrefix("origin/") {
            return String(ref.dropFirst("origin/".count))
        }
        if hasOrigin(root), let out = try? Git.run(["ls-remote", "--symref", "origin", "HEAD"], in: root),
           let line = out.split(separator: "\n").first(where: { $0.hasPrefix("ref: refs/heads/") }) {
            return String(line.dropFirst("ref: refs/heads/".count).prefix { $0 != "\t" && $0 != " " })
        }
        return "main"
    }

    private func hasOrigin(_ root: String) -> Bool {
        ((try? Git.run(["remote"], in: root)) ?? "").split(separator: "\n").contains("origin")
    }

    private func stashCount(_ dir: String) -> Int {
        ((try? Git.run(["stash", "list"], in: dir)) ?? "").split(separator: "\n").count
    }

    public func push(dir: String) throws -> (output: String, exitCode: Int32) {
        let c = try myClaim(dir: dir)
        let checkout = c.worktree ?? c.repoRoot
        let lock = RepoLock(paths: paths, repoRoot: c.repoRoot)
        try lock.acquire()
        defer { lock.release() }

        guard hasOrigin(c.repoRoot) else { return ("NO_REMOTE", 2) }
        let target = defaultBranch(root: c.repoRoot)
        let branch = c.worktree == nil ? try Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: checkout) : target
        guard branch != "HEAD" else { throw OnyxError.git("detached HEAD in \(checkout); check out a branch first") }
        try Git.run(["fetch", "-q", "origin"], in: checkout)
        let upstream = Git.result(["rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(branch)"], in: checkout).status == 0
            ? "origin/\(branch)" : "origin/\(target)"

        let stashesBefore = stashCount(checkout)
        let rebase = Git.result(["rebase", "--autostash", upstream], in: checkout)
        if rebase.status != 0 {
            let files = (try? Git.run(["diff", "--name-only", "--diff-filter=U"], in: checkout)) ?? ""
            if files.isEmpty { throw OnyxError.git(rebase.err.isEmpty ? rebase.out : rebase.err) }
            return ("CONFLICT " + files.split(separator: "\n").joined(separator: " "), 1)
        }
        // git exits 0 even when the autostash could not be re-applied; the edits then sit in the stash.
        let stashed = stashCount(checkout) > stashesBefore
        try Git.run(["push", "-q", "origin", "HEAD:refs/heads/\(branch)"], in: checkout)
        let sha = try Git.run(["rev-parse", "--short", "HEAD"], in: checkout)
        return ("PUSHED \(sha)" + (stashed ? " STASHED" : ""), 0)
    }

    public func release(dir: String) throws -> String {
        let c = try myClaim(dir: dir)
        registry.remove(paneId: paneId, repoRoot: c.repoRoot)
        guard let wt = c.worktree else { return "RELEASED" }
        let root = c.repoRoot
        let dirty = !((try? Git.run(["status", "--porcelain"], in: wt)) ?? "").isEmpty
        if dirty { return "RELEASED kept-worktree \(wt) dirty" }
        let target = defaultBranch(root: root)
        var base = target
        if hasOrigin(root) {
            _ = Git.result(["fetch", "-q", "origin"], in: root)
            base = "origin/\(target)"
        }
        let merged = Git.result(["merge-base", "--is-ancestor", c.branch, base], in: root).status == 0
        guard merged else { return "RELEASED kept-worktree \(wt)" }
        try Git.run(["worktree", "remove", wt], in: root)
        try Git.run(["branch", "-D", c.branch], in: root)
        return "RELEASED removed-worktree \(root)"
    }
}
