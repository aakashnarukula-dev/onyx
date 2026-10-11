import Foundation

/// Onyx's support directory: `$ONYX_HOME`, else `~/Library/Application Support/Onyx`.
public struct OnyxPaths: Sendable {
    public let home: URL

    public init(env: [String: String] = ProcessInfo.processInfo.environment) {
        if let h = env["ONYX_HOME"], !h.isEmpty {
            home = URL(fileURLWithPath: h)
        } else {
            let user = env["HOME"] ?? NSHomeDirectory()
            home = URL(fileURLWithPath: user).appendingPathComponent("Library/Application Support/Onyx")
        }
    }

    public var panes: URL { home.appendingPathComponent("panes") }
    public var locks: URL { home.appendingPathComponent("locks") }
    public var settings: URL { home.appendingPathComponent("settings.json") }
    public var prompt: URL { home.appendingPathComponent("pane-prompt.md") }
}

public enum OnyxError: Error, Equatable {
    case lockTimeout
    case notARepo(String)
    case git(String)
}

@Sendable public func isProcessAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
