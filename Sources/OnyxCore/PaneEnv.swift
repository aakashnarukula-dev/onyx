import Foundation

/// How a pane's shell is started: the user's own login shell and environment, as Terminal.app
/// would give it, with Claude launched first.
public enum PaneEnv {
    /// Runs Claude in auto mode; if it is not installed, says so. Either way a normal shell follows.
    public static let claudeCommand =
        "if command -v claude >/dev/null 2>&1; then claude --permission-mode auto; "
        + "else printf '\\033[2mclaude not found — plain shell\\033[0m\\n'; fi"

    public static func build(base: [String: String]) -> [String: String] {
        var env = base
        // Markers from a Claude session that launched Onyx would make each pane's Claude think
        // it is a child session. The login shell re-reads the user's own settings anyway.
        for k in env.keys where k == "CLAUDECODE" || k.hasPrefix("CLAUDE_CODE_") { env[k] = nil }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Onyx"
        // Finder-launched apps get no LANG; Terminal.app sets one so UTF-8 text works.
        if env["LANG"]?.isEmpty ?? true { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    /// Arguments for the login shell: run `command`, then become an ordinary interactive shell.
    public static func shellArgs(shell: String, command: String) -> [String] {
        let quoted = "'" + shell.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return ["-l", "-i", "-c", "\(command); exec \(quoted) -l -i"]
    }

    /// The user's login shell from the account database, else zsh.
    public static func loginShell(passwdShell: String? = currentUserShell()) -> String {
        if let s = passwdShell, FileManager.default.isExecutableFile(atPath: s) { return s }
        return "/bin/zsh"
    }

    public static func currentUserShell() -> String? {
        guard let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell else { return nil }
        return String(cString: sh)
    }
}
