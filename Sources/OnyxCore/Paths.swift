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

    public var settings: URL { home.appendingPathComponent("settings.json") }
    public var session: URL { home.appendingPathComponent("session.json") }
}
