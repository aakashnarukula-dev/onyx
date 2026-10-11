import CryptoKit
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

/// Short stable id for a repo path (lock and claim file names).
func repoKey(_ repoRoot: String) -> String {
    SHA256.hash(data: Data(repoRoot.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

/// File-based registry shared by every pane:
/// - `panes/<id>.pid` (written by the app): "<shell pid> <start time>", so a reused pid reads as dead;
/// - `panes/<id>@<repoKey>.json`: one claim per repo the pane works in.
public struct PaneRegistry: Sendable {
    let paths: OnyxPaths
    let startTime: @Sendable (Int32) -> UInt64?
    private var fm: FileManager { .default }

    public init(paths: OnyxPaths, startTime: @escaping @Sendable (Int32) -> UInt64? = processStartTime) {
        self.paths = paths
        self.startTime = startTime
    }

    private func pidURL(_ id: String) -> URL { paths.panes.appendingPathComponent("\(id).pid") }
    private func claimURL(_ id: String, _ repoRoot: String) -> URL {
        paths.panes.appendingPathComponent("\(id)@\(repoKey(repoRoot)).json")
    }

    public func markAlive(paneId: String, pid: Int32) throws {
        try fm.createDirectory(at: paths.panes, withIntermediateDirectories: true)
        guard let start = startTime(pid) else { return }
        try "\(pid) \(start)".write(to: pidURL(paneId), atomically: true, encoding: .utf8)
    }

    /// Removes the pane's pid file and all of its claims.
    public func markClosed(paneId: String) {
        try? fm.removeItem(at: pidURL(paneId))
        let names = (try? fm.contentsOfDirectory(atPath: paths.panes.path)) ?? []
        for n in names where n.hasPrefix("\(paneId)@") {
            try? fm.removeItem(at: paths.panes.appendingPathComponent(n))
        }
    }

    public func save(_ c: PaneClaim) throws {
        try fm.createDirectory(at: paths.panes, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(c).write(to: claimURL(c.paneId, c.repoRoot), options: .atomic)
    }

    public func remove(paneId: String, repoRoot: String) {
        try? fm.removeItem(at: claimURL(paneId, repoRoot))
    }

    /// This pane's claim on one repo, if the pane is alive.
    public func claim(paneId: String, repoRoot: String) -> PaneClaim? {
        live().first { $0.paneId == paneId && $0.repoRoot == repoRoot }
    }

    private func isAlive(_ id: String) -> Bool {
        guard let text = try? String(contentsOf: pidURL(id), encoding: .utf8) else { return false }
        let parts = text.split(separator: " ")
        guard parts.count == 2, let pid = Int32(parts[0]), pid > 0, let start = UInt64(parts[1]) else { return false }
        return startTime(pid) == start
    }

    /// Claims of panes whose shell is still running, sorted by pane id then repo. Dead ones are pruned.
    public func live() -> [PaneClaim] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let names = (try? fm.contentsOfDirectory(atPath: paths.panes.path)) ?? []
        var alive: [String: Bool] = [:]
        var out: [PaneClaim] = []
        for name in names where name.hasSuffix(".json") {
            let id = String(name.prefix { $0 != "@" })
            let ok = alive[id] ?? isAlive(id)
            alive[id] = ok
            let url = paths.panes.appendingPathComponent(name)
            guard ok, let data = try? Data(contentsOf: url), let c = try? dec.decode(PaneClaim.self, from: data) else {
                if !ok { markClosed(paneId: id) } else { try? fm.removeItem(at: url) }
                continue
            }
            out.append(c)
        }
        return out.sorted { ($0.paneId, $0.repoRoot) < ($1.paneId, $1.repoRoot) }
    }
}
