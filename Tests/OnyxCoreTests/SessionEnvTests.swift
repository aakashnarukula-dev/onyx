import Foundation
import Testing
@testable import OnyxCore

struct SessionEnvTests {
    func setup(ghOK: Bool) -> (Settings, AccountStore) {
        let r = FakeRunner()
        if ghOK { r.replies["gh auth token -u foo"] = (0, "gho_abc\n", "") }
        r.replies["gh api user"] = (0, #"{"login":"foo","id":7,"name":"Foo","email":"foo@x.com"}"#, "")
        let secrets = MemorySecrets()
        try? secrets.set("work", "vc_tok")
        var s = Settings()
        s.activeGitHub = "foo"; s.activeVercel = "work"; s.vercelLabels = ["work"]
        return (s, AccountStore(paths: tempPaths(), secrets: secrets, run: r.run))
    }

    @Test func envWithTokens() {
        let (s, a) = setup(ghOK: true)
        let env = SessionEnv.build(base: ["PATH": "/usr/bin", "HOME": "/h"], settings: s, accounts: a, paneId: "p1", binDir: "/App/MacOS")
        #expect(env["GH_TOKEN"] == "gho_abc")
        #expect(env["GIT_AUTHOR_NAME"] == "Foo")
        #expect(env["GIT_AUTHOR_EMAIL"] == "foo@x.com")
        #expect(env["GIT_COMMITTER_EMAIL"] == "foo@x.com")
        #expect(env["VERCEL_TOKEN"] == "vc_tok")
        #expect(env["PATH"] == "/App/MacOS:/usr/bin")
        #expect(env["ONYX_PANE_ID"] == "p1")
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["HOME"] == "/h")
    }

    @Test func ghTokenFailureOmitsGitHubVars() {
        let (s, a) = setup(ghOK: false)
        let env = SessionEnv.build(base: [:], settings: s, accounts: a, paneId: "p1", binDir: "/b")
        #expect(env["GH_TOKEN"] == nil)
        #expect(env["GIT_AUTHOR_NAME"] == nil)
        #expect(env["VERCEL_TOKEN"] == "vc_tok")
        #expect(env["ONYX_PANE_ID"] == "p1")
    }

    @Test func noActiveAccounts() {
        let (_, a) = setup(ghOK: true)
        let env = SessionEnv.build(base: [:], settings: Settings(), accounts: a, paneId: "p", binDir: "/b")
        #expect(env["GH_TOKEN"] == nil && env["VERCEL_TOKEN"] == nil)
    }

    @Test func scrubsInheritedAccountVars() {
        let (_, a) = setup(ghOK: true)
        let env = SessionEnv.build(base: ["GH_TOKEN": "old", "VERCEL_TOKEN": "old", "GIT_AUTHOR_NAME": "old"],
                                   settings: Settings(), accounts: a, paneId: "p", binDir: "/b")
        #expect(env["GH_TOKEN"] == nil && env["VERCEL_TOKEN"] == nil && env["GIT_AUTHOR_NAME"] == nil)
    }
}

struct SessionEnvSplitTests {
    @Test func cachedAccountVarsAreApplied() {
        let env = SessionEnv.build(base: ["GH_TOKEN": "stale"], accountVars: ["GH_TOKEN": "fresh"], paneId: "p", binDir: "/b")
        #expect(env["GH_TOKEN"] == "fresh")
        #expect(env["ONYX_PANE_ID"] == "p")
    }
}

struct SessionEnvScrubTests {
    @Test func dropsInheritedClaudeSessionMarkers() {
        let env = SessionEnv.build(base: ["CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "x", "CLAUDE_CODE_ENTRYPOINT": "cli", "KEEP": "1"],
                                   accountVars: [:], paneId: "p", binDir: "/b")
        #expect(env["CLAUDECODE"] == nil && env["CLAUDE_CODE_CHILD_SESSION"] == nil && env["CLAUDE_CODE_ENTRYPOINT"] == nil)
        #expect(env["KEEP"] == "1")
    }
}
