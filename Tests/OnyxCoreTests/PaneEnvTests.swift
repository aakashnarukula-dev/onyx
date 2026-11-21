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

    @Test func plainShellStartsWithoutAssistantOrCommandWrapper() {
        for shell in ["/bin/zsh", "/bin/bash", "/usr/local/bin/fish"] {
            let launch = PaneEnv.launch(shell: shell, firstCommand: "", zdotdir: "/z", userZdotdir: "/user")
            #expect(launch.args.isEmpty)
            #expect(launch.execName == "-" + URL(fileURLWithPath: shell).lastPathComponent)
            #expect(launch.env.isEmpty)
        }
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

    @Test func bothAssistantsLaunchThroughLoginShells() {
        for assistant in Assistant.allCases {
            let zsh = PaneEnv.launch(shell: "/bin/zsh", firstCommand: assistant.command, zdotdir: "/z", userZdotdir: nil)
            #expect(zsh.env["ONYX_FIRST_COMMAND"] == assistant.command)
            let bash = PaneEnv.launch(shell: "/bin/bash", firstCommand: assistant.command, zdotdir: "/z", userZdotdir: nil)
            #expect(bash.args[3].contains("command -v \(assistant.rawValue)"))
            #expect(bash.args[3].contains(assistant.command))
        }
        #expect(Assistant.codex.command == "codex --sandbox danger-full-access --ask-for-approval never -c 'tui.terminal_title=[\"session-id\"]'")
        #expect(Assistant.claude.command == "claude --permission-mode auto")
    }

    @Test func freshAndRestoredCodexPanesUseFullAccessInBothShells() {
        for resuming in [false, true] {
            let command = PaneEnv.codexCommand(resuming: resuming)
            let expected = resuming ? "codex resume" : "codex"
            #expect(command == "\(expected) --sandbox danger-full-access --ask-for-approval never -c 'tui.terminal_title=[\"session-id\"]'")
            let zsh = PaneEnv.launch(shell: "/bin/zsh", firstCommand: command, zdotdir: "/z", userZdotdir: nil)
            #expect(zsh.env["ONYX_FIRST_COMMAND"] == command)
            let bash = PaneEnv.launch(shell: "/bin/bash", firstCommand: command, zdotdir: "/z", userZdotdir: nil)
            #expect(bash.args[3].contains("then \(command);"))
        }
    }

    @Test func codexRestoresExactIDAndNeverInterpolatesInvalidIDs() {
        let id = "01a1f325-83ee-7cf0-8f86-3035e0d4af5d"
        #expect(PaneEnv.codexCommand(resuming: true, sessionID: id).hasPrefix("codex resume \(id) --sandbox"))
        for invalid in ["$(touch /tmp/injected)", "x; exit", "--last", ""] {
            #expect(PaneEnv.codexCommand(resuming: true, sessionID: invalid) == PaneEnv.codexCommand(resuming: true))
        }
    }

    @Test func failedExactResumeFallsBackOnceButSuccessAndInterruptDoNot() {
        let id = "01a1f325-83ee-7cf0-8f86-3035e0d4af5d"
        let command = PaneEnv.codexCommand(resuming: true, sessionID: id)
        for shell in ["/bin/zsh", "/bin/bash"] {
            for status in [0, 1, 130] {
                let stub = "codex() { printf '%s\\n' \"$*\"; if [ \"$2\" = '\(id)' ]; then return \(status); fi; return 0; }; "
                let result = Shell.run(shell, ["-c", stub + command])
                let calls = result.out.split(separator: "\n")
                #expect(calls.count == (status == 1 ? 2 : 1))
                #expect(calls.first?.hasPrefix("resume \(id) ") == true)
                if status == 1 { #expect(calls.last?.hasPrefix("resume --sandbox") == true) }
            }
        }
    }

    @Test func loginShellFallsBackToZsh() {
        #expect(PaneEnv.loginShell(passwdShell: nil) == "/bin/zsh")
        #expect(PaneEnv.loginShell(passwdShell: "/bin/bash") == "/bin/bash")
        #expect(PaneEnv.loginShell(passwdShell: "/nonexistent/sh") == "/bin/zsh")
    }
}
