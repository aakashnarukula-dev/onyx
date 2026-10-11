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

/// True if `pid` names a running process. 0 and negatives are process groups, never a pane.
@Sendable public func isProcessAlive(_ pid: Int32) -> Bool { pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) }

/// Start time (µs since epoch) of a running process, nil if there is none. Paired with the pid it
/// identifies a process even after the pid number is reused.
@Sendable public func processStartTime(_ pid: Int32) -> UInt64? {
    guard pid > 0 else { return nil }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
}
