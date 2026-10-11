import Foundation

/// What a pane is working on in a repo.
public struct PaneClaim: Codable, Equatable, Sendable {
    public var paneId: String
    public var repoRoot: String
    public var worktree: String?
    public var branch: String
    public var task: String
    public var updatedAt: Date

    public init(paneId: String, repoRoot: String, worktree: String?, branch: String, task: String, updatedAt: Date) {
        self.paneId = paneId; self.repoRoot = repoRoot; self.worktree = worktree
        self.branch = branch; self.task = task; self.updatedAt = updatedAt
    }
}

/// File-based registry shared by every pane: `panes/<id>.pid` (written by the app,
/// holds the pane's shell pid) and `panes/<id>.json` (the pane's claim).
public struct PaneRegistry: Sendable {
    let paths: OnyxPaths
    let isAlive: @Sendable (Int32) -> Bool
    private var fm: FileManager { .default }

    public init(paths: OnyxPaths, isAlive: @escaping @Sendable (Int32) -> Bool = isProcessAlive) {
        self.paths = paths
        self.isAlive = isAlive
    }

    private func pidURL(_ id: String) -> URL { paths.panes.appendingPathComponent("\(id).pid") }
    private func claimURL(_ id: String) -> URL { paths.panes.appendingPathComponent("\(id).json") }

    public func markAlive(paneId: String, pid: Int32) throws {
        try fm.createDirectory(at: paths.panes, withIntermediateDirectories: true)
        try String(pid).write(to: pidURL(paneId), atomically: true, encoding: .utf8)
    }

    public func markClosed(paneId: String) {
        try? fm.removeItem(at: pidURL(paneId))
        try? fm.removeItem(at: claimURL(paneId))
    }

    public func save(_ c: PaneClaim) throws {
        try fm.createDirectory(at: paths.panes, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(c).write(to: claimURL(c.paneId), options: .atomic)
    }

    public func remove(paneId: String) {
        try? fm.removeItem(at: claimURL(paneId))
    }

    /// The claim for one pane, if that pane is alive.
    public func claim(paneId: String) -> PaneClaim? {
        live().first { $0.paneId == paneId }
    }

    /// Claims of panes whose shell is still running, sorted by pane id. Dead ones are pruned.
    public func live() -> [PaneClaim] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let names = (try? fm.contentsOfDirectory(atPath: paths.panes.path)) ?? []
        var out: [PaneClaim] = []
        for name in names where name.hasSuffix(".json") {
            let id = String(name.dropLast(5))
            let pid = (try? String(contentsOf: pidURL(id), encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard let pid, isAlive(pid),
                  let data = try? Data(contentsOf: claimURL(id)),
                  let c = try? dec.decode(PaneClaim.self, from: data) else {
                markClosed(paneId: id)
                continue
            }
            out.append(c)
        }
        return out.sorted { $0.paneId < $1.paneId }
    }
}
