import Foundation

/// What was open (`session.json`): each window's frame and, per terminal, its folder and the
/// Claude conversation running there. Kept current while Onyx runs, so a force quit or crash
/// leaves it behind for the next launch to reopen.
public struct SessionState: Codable, Equatable, Sendable {
    public struct Pane: Codable, Equatable, Sendable {
        public var cwd: String
        public var claudeSession: String?

        public init(cwd: String, claudeSession: String?) {
            self.cwd = cwd
            self.claudeSession = claudeSession
        }
    }

    public struct Window: Codable, Equatable, Sendable {
        public var frame: [Double]  // x, y, width, height
        public var panes: [Pane]

        public init(frame: [Double], panes: [Pane]) {
            self.frame = frame
            self.panes = panes
        }
    }

    public var windows: [Window]

    public init(windows: [Window]) { self.windows = windows }

    public static func load(_ paths: OnyxPaths) -> SessionState? {
        guard let data = try? Data(contentsOf: paths.session) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    /// Writes the file if it differs from what is there. True if it wrote.
    @discardableResult
    public func save(_ paths: OnyxPaths) throws -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        if (try? Data(contentsOf: paths.session)) == data { return false }
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try data.write(to: paths.session, options: .atomic)
        return true
    }
}

/// Claude Code's own records (in `~/.claude`, or `$CLAUDE_CONFIG_DIR`): which conversation a
/// running `claude` process is in, and whether a conversation was saved.
public struct ClaudeSessions: Sendable {
    public struct Running: Equatable, Sendable {
        public let id: String
        public let cwd: String
    }

    public let configDir: URL

    public init(configDir: URL) { self.configDir = configDir }

    public init(env: [String: String] = ProcessInfo.processInfo.environment) {
        if let d = env["CLAUDE_CONFIG_DIR"], !d.isEmpty {
            configDir = URL(fileURLWithPath: d)
        } else {
            configDir = URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory()).appendingPathComponent(".claude")
        }
    }

    /// The conversation of the `claude` process `pid`, from `sessions/<pid>.json` (which Claude
    /// keeps current, including after `/clear`).
    public func running(pid: Int32) -> Running? {
        let url = configDir.appendingPathComponent("sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["pid"] as? NSNumber)?.int32Value == pid,
              let id = obj["sessionId"] as? String, Self.isSessionId(id),
              let cwd = obj["cwd"] as? String else { return nil }
        return Running(id: id, cwd: cwd)
    }

    /// Claude writes a conversation to `projects/<folder>/<id>.jsonl` once it has a message;
    /// one that never got a message can't be resumed.
    public func hasTranscript(id: String) -> Bool {
        guard Self.isSessionId(id) else { return false }
        let projects = configDir.appendingPathComponent("projects")
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return dirs.contains {
            FileManager.default.fileExists(atPath: projects.appendingPathComponent("\($0)/\(id).jsonl").path)
        }
    }

    public static func resumeCommand(id: String) -> String {
        "claude --resume \(id) --permission-mode auto"
    }

    /// Session ids are UUIDs; anything else is never typed into a shell.
    static func isSessionId(_ s: String) -> Bool {
        UUID(uuidString: s) != nil
    }
}
