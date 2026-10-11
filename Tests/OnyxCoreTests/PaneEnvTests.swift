import Foundation
import Testing
@testable import OnyxCore

struct PaneEnvTests {
    @Test func addsTerminalVars() {
        let env = PaneEnv.build(base: ["PATH": "/usr/bin", "HOME": "/h"])
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "Onyx")
        #expect(env["PATH"] == "/usr/bin" && env["HOME"] == "/h")
    }

    /// Apps opened from Finder get no LANG; without it zsh and Claude mangle non-ASCII text.
    @Test func setsUTF8LocaleWhenMissing() {
        #expect(PaneEnv.build(base: [:])["LANG"] == "en_US.UTF-8")
        #expect(PaneEnv.build(base: ["LANG": "de_DE.UTF-8"])["LANG"] == "de_DE.UTF-8")
    }

    /// Your own logins stay exactly as your shell has them: nothing account-related is touched.
    @Test func leavesAccountsAlone() {
        let env = PaneEnv.build(base: ["GH_TOKEN": "t", "GIT_AUTHOR_NAME": "me", "VERCEL_TOKEN": "v"])
        #expect(env["GH_TOKEN"] == "t" && env["GIT_AUTHOR_NAME"] == "me" && env["VERCEL_TOKEN"] == "v")
    }

    @Test func dropsInheritedClaudeSessionMarkers() {
        let env = PaneEnv.build(base: ["CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "x", "KEEP": "1"])
        #expect(env["CLAUDECODE"] == nil && env["CLAUDE_CODE_CHILD_SESSION"] == nil)
        #expect(env["KEEP"] == "1")
    }

    @Test func startupCommandRunsClaudeThenAShell() {
        let args = PaneEnv.shellArgs(shell: "/bin/zsh", command: PaneEnv.claudeCommand)
        #expect(args.prefix(3) == ["-l", "-i", "-c"])
        #expect(args[3].contains("claude --permission-mode auto"))
        #expect(args[3].hasSuffix("; exec '/bin/zsh' -l -i"))
        #expect(!args[3].contains("append-system-prompt"))
    }

    @Test func loginShellFallsBackToZsh() {
        #expect(PaneEnv.loginShell(passwdShell: nil) == "/bin/zsh")
        #expect(PaneEnv.loginShell(passwdShell: "/bin/bash") == "/bin/bash")
        #expect(PaneEnv.loginShell(passwdShell: "/nonexistent/sh") == "/bin/zsh")
    }
}
