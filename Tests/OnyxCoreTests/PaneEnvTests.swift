import Foundation
import Testing
@testable import OnyxCore

struct PaneEnvTests {
    @Test func addsTerminalVars() {
        let env = PaneEnv.build(base: ["PATH": "/usr/bin", "HOME": "/h"], locale: nil)
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "Onyx")
        #expect(env["PATH"] == "/usr/bin" && env["HOME"] == "/h")
    }

    /// Like Terminal.app: LANG from the user's region when the launcher gave none.
    @Test func localeFromRegion() {
        #expect(PaneEnv.build(base: [:], locale: "en_IN")["LANG"] == "en_IN.UTF-8")
        #expect(PaneEnv.build(base: [:], locale: "xx_NOPE")["LANG"] == "en_US.UTF-8")
        #expect(PaneEnv.build(base: [:], locale: nil)["LANG"] == "en_US.UTF-8")
        #expect(PaneEnv.build(base: ["LANG": "de_DE.UTF-8"], locale: "en_IN")["LANG"] == "de_DE.UTF-8")
    }

    @Test func leavesAccountsAlone() {
        let env = PaneEnv.build(base: ["GH_TOKEN": "t", "GIT_AUTHOR_NAME": "me", "VERCEL_TOKEN": "v"], locale: nil)
        #expect(env["GH_TOKEN"] == "t" && env["GIT_AUTHOR_NAME"] == "me" && env["VERCEL_TOKEN"] == "v")
    }

    @Test func dropsLauncherTerminalAndClaudeVars() {
        let base = ["CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "x", "TERM_PROGRAM_VERSION": "455",
                    "TERM_SESSION_ID": "w0", "TMUX": "/t", "TMUX_PANE": "%1", "ITERM_SESSION_ID": "i",
                    "VSCODE_PID": "1", "SHLVL": "3", "KEEP": "1"]
        let env = PaneEnv.build(base: base, locale: nil)
        for k in base.keys where k != "KEEP" { #expect(env[k] == nil, "\(k) leaked") }
        #expect(env["KEEP"] == "1")
    }

    @Test func zshStartsAsPlainLoginShellWithFirstCommand() {
        let l = PaneEnv.launch(shell: "/bin/zsh", firstCommand: "claude --permission-mode auto",
                               zdotdir: "/onyx/zsh", userZdotdir: "/u/zdot")
        #expect(l.args.isEmpty)                      // login + interactive, like Terminal.app
        #expect(l.execName == "-zsh")
        #expect(l.env["ZDOTDIR"] == "/onyx/zsh")
        #expect(l.env["ONYX_USER_ZDOTDIR"] == "/u/zdot")
        #expect(l.env["ONYX_FIRST_COMMAND"] == "claude --permission-mode auto")
    }

    @Test func otherShellsFallBackToCommandThenShell() {
        let l = PaneEnv.launch(shell: "/bin/bash", firstCommand: "claude --permission-mode auto", zdotdir: "/z", userZdotdir: nil)
        #expect(l.args.prefix(3) == ["-l", "-i", "-c"])
        #expect(l.args[3].contains("claude --permission-mode auto"))
        #expect(l.args[3].hasSuffix("; exec '/bin/bash' -l -i"))
        #expect(l.env["ZDOTDIR"] == nil)
    }

    @Test func zshIntegrationRestoresUserSetupAndRunsCommandOnce() throws {
        let s = ZshIntegration.zshenv
        #expect(s.contains(#"ZDOTDIR="$ONYX_USER_ZDOTDIR""#))
        #expect(s.contains("unset ZDOTDIR"))
        #expect(s.contains(#"source "${ZDOTDIR:-$HOME}/.zshenv""#))
        #expect(s.contains("add-zle-hook-widget -d zle-line-init"))
        #expect(s.contains("zle accept-line"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let out = try ZshIntegration.write(to: dir)
        #expect(try String(contentsOf: out.appendingPathComponent(".zshenv"), encoding: .utf8) == s)
    }

    @Test func loginShellFallsBackToZsh() {
        #expect(PaneEnv.loginShell(passwdShell: nil) == "/bin/zsh")
        #expect(PaneEnv.loginShell(passwdShell: "/bin/bash") == "/bin/bash")
        #expect(PaneEnv.loginShell(passwdShell: "/nonexistent/sh") == "/bin/zsh")
    }
}
