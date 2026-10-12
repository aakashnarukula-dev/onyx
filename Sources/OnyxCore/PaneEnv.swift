import Foundation

/// How a pane's shell is started: the user's own login shell and environment, as Terminal.app
/// would give it, with Claude run as the first command.
public enum PaneEnv {
    public static let claudeCommand = "claude --permission-mode auto"

    /// Variables other terminals (or a Claude session) set to describe themselves. Passing them on
    /// would make tools in the pane think they run inside that terminal.
    static func isLauncherVar(_ k: String) -> Bool {
        k == "CLAUDECODE" || k.hasPrefix("CLAUDE_CODE_") || k == "SHLVL"
            || ["TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "TMUX", "TMUX_PANE", "STY", "WINDOWID"].contains(k)
            || ["ITERM_", "VSCODE_", "KITTY_", "WEZTERM_", "GHOSTTY_", "ALACRITTY_", "WARP_"].contains { k.hasPrefix($0) }
    }

    /// `locale` is the user's region identifier (e.g. "en_IN"), used for LANG when none is set.
    public static func build(base: [String: String], locale: String? = Locale.current.identifier) -> [String: String] {
        var env = base
        for k in env.keys where isLauncherVar(k) { env[k] = nil }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Onyx"
        // Finder-launched apps get no LANG; Terminal.app derives one from the region.
        if env["LANG"]?.isEmpty ?? true {
            let candidate = locale.map { "\($0).UTF-8" }
            let exists = candidate.map { FileManager.default.fileExists(atPath: "/usr/share/locale/\($0)") } ?? false
            env["LANG"] = exists ? candidate! : "en_US.UTF-8"
        }
        return env
    }

    public struct Launch: Equatable {
        public let args: [String]
        public let execName: String
        public let env: [String: String]
    }

    /// zsh starts exactly as in Terminal.app (login + interactive, startup files read once) and runs
    /// `firstCommand` from its prompt, so job control (Ctrl-Z / fg) works. Other shells run the
    /// command through `-c` and then become an interactive shell.
    public static func launch(shell: String, firstCommand: String, zdotdir: String, userZdotdir: String?) -> Launch {
        let name = (shell as NSString).lastPathComponent
        if name == "zsh" {
            var env = ["ZDOTDIR": zdotdir, "ONYX_FIRST_COMMAND": firstCommand]
            if let userZdotdir { env["ONYX_USER_ZDOTDIR"] = userZdotdir }
            return Launch(args: [], execName: "-" + name, env: env)
        }
        let quoted = "'" + shell.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let guarded = firstCommand.hasPrefix("claude")
            ? "if command -v claude >/dev/null 2>&1; then \(firstCommand); "
              + "else printf '\\033[2mclaude not found — plain shell\\033[0m\\n'; fi"
            : firstCommand
        return Launch(args: ["-l", "-i", "-c", "\(guarded); exec \(quoted) -l -i"], execName: "-" + name, env: [:])
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

/// A one-file ZDOTDIR that hands zsh straight back to the user's own startup files, then types the
/// first command at the first prompt (as if the user typed it).
public enum ZshIntegration {
    public static let zshenv = #"""
    # Onyx: give zsh back the user's own startup files, then run one command at the first prompt.
    if [[ -n "${ONYX_USER_ZDOTDIR-}" ]]; then ZDOTDIR="$ONYX_USER_ZDOTDIR"; else unset ZDOTDIR; fi
    unset ONYX_USER_ZDOTDIR
    [[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]] && source "${ZDOTDIR:-$HOME}/.zshenv"

    if [[ -o interactive && -n "${ONYX_FIRST_COMMAND-}" ]]; then
      typeset -g _onyx_first="$ONYX_FIRST_COMMAND"
      unset ONYX_FIRST_COMMAND
      # Set up after the user's .zshrc (first precmd), so their own line-init widgets stay intact.
      _onyx_arm() {
        precmd_functions=(${precmd_functions:#_onyx_arm})
        autoload -Uz add-zle-hook-widget
        zle -N _onyx_type_first
        add-zle-hook-widget zle-line-init _onyx_type_first
      }
      _onyx_type_first() {
        add-zle-hook-widget -d zle-line-init _onyx_type_first
        if [[ "$_onyx_first" == claude* ]] && (( ! $+commands[claude] )); then
          zle -M 'claude not found — plain shell'
        else
          BUFFER="$_onyx_first"
          zle accept-line
        fi
        unset _onyx_first
      }
      precmd_functions+=(_onyx_arm)
    fi
    """# + "\n"

    /// Writes `.zshenv` into `dir` and returns `dir`.
    public static func write(to dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try zshenv.write(to: dir.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
        return dir
    }
}

/// ⌘K, as in Terminal.app: clear the screen and scrollback, then ask the program to redraw.
public enum TerminalClear {
    /// Fed to the terminal display (not the program): home, erase screen, erase scrollback.
    public static let localSequence = "\u{1b}[H\u{1b}[2J\u{1b}[3J"
    /// Sent to the program: Ctrl-L, which zsh and Claude both answer by redrawing.
    public static let redrawKey: [UInt8] = [0x0c]
}

/// Files dropped on a terminal, typed as Terminal.app types them: each path with shell
/// characters backslash-escaped, separated by spaces, plus a trailing space.
public enum DroppedFiles {
    static let special = Set(#" \'"$`!&*()[]{};<>?|#~"#.map { $0 }).union(["\t"])

    public static func text(for paths: [String]) -> String {
        paths.map { path in
            path.map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
        }.joined(separator: " ") + " "
    }
}

/// Terminal titles as text for a sentence: Claude puts a status symbol in front of its title
/// ("✳ Fix login bug", "◑ …" while working), which is dropped.
public enum PaneTitle {
    public static func plain(_ title: String) -> String {
        guard let first = title.unicodeScalars.first, title.count > 2,
              !CharacterSet.alphanumerics.union(.punctuationCharacters).contains(first),
              title.dropFirst().first == " " else { return title }
        return String(title.dropFirst(2))
    }
}
