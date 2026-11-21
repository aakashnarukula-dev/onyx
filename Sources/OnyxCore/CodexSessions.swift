import Foundation

/// Codex's per-terminal OSC title identifies the conversation even when several terminals use
/// the same folder or share an app-server daemon. Never infer identity from the newest chat.
public struct CodexSessions: Sendable {
    public let configDir: URL

    public init(configDir: URL) { self.configDir = configDir }

    public init(env: [String: String] = ProcessInfo.processInfo.environment) {
        let home = env["HOME"] ?? NSHomeDirectory()
        configDir = URL(fileURLWithPath: env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.codex")
    }

    public static func isSessionTitle(_ title: String) -> Bool {
        if UUID(uuidString: title) != nil { return true }
        // Codex shortens the title's thread item, including an ellipsis.
        guard title.hasSuffix("...") || title.hasSuffix("…") else { return false }
        let prefix = title.hasSuffix("...") ? String(title.dropLast(3)) : String(title.dropLast())
        let shape = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        guard (24..<36).contains(prefix.count) else { return false }
        return zip(prefix, shape).allSatisfy { c, expected in
            expected == "-" ? c == "-" : c.isASCII && c.isHexDigit
        }
    }

    public static func title(_ title: String, matches sessionID: String) -> Bool {
        guard isSessionTitle(title), UUID(uuidString: sessionID) != nil else { return false }
        let prefix = title.hasSuffix("...") ? String(title.dropLast(3))
            : title.hasSuffix("…") ? String(title.dropLast()) : title
        return sessionID.lowercased().hasPrefix(prefix.lowercased())
    }

    /// Resolve a shortened ID only when Codex's own records contain exactly one match.
    /// Reading filenames/index IDs avoids depending on transcript content or SQLite schemas.
    public func sessionID(fromTitle title: String) -> String? {
        guard Self.isSessionTitle(title) else { return nil }
        if UUID(uuidString: title) != nil { return title }
        let prefix = (title.hasSuffix("...") ? String(title.dropLast(3)) : String(title.dropLast())).lowercased()
        var ids = Set<String>()
        let snapshots = configDir.appendingPathComponent("shell_snapshots")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: snapshots.path)) ?? [] {
            let id = String(name.prefix(36)).lowercased()
            if UUID(uuidString: id) != nil, id.hasPrefix(prefix) { ids.insert(id) }
        }
        // The index also covers saved chats when shell snapshots are disabled or cleaned up.
        if let data = try? Data(contentsOf: configDir.appendingPathComponent("session_index.jsonl")) {
            struct Entry: Decodable { let id: String }
            for line in data.split(separator: 10) {
                guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line)) else { continue }
                let id = entry.id.lowercased()
                if UUID(uuidString: id) != nil, id.hasPrefix(prefix) { ids.insert(id) }
            }
        }
        return ids.count == 1 ? ids.first : nil
    }
}
