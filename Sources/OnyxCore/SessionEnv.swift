import Foundation

/// Environment for a new pane's shell, carrying the active GitHub + Vercel accounts.
public enum SessionEnv {
    static let accountKeys = ["GH_TOKEN", "GITHUB_TOKEN", "VERCEL_TOKEN",
                              "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"]

    public static func build(base: [String: String], settings: Settings, accounts: AccountStore,
                             paneId: String, binDir: String) -> [String: String] {
        build(base: base, accountVars: accountVars(settings: settings, accounts: accounts), paneId: paneId, binDir: binDir)
    }

    /// Pane env from precomputed account vars (cheap: no subprocesses).
    public static func build(base: [String: String], accountVars: [String: String],
                             paneId: String, binDir: String) -> [String: String] {
        var env = base
        for k in accountKeys { env[k] = nil }
        env["ONYX_PANE_ID"] = paneId
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Onyx"
        env["PATH"] = [binDir, base["PATH"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ":")
        env.merge(accountVars) { _, new in new }
        return env
    }

    /// Account vars for the active accounts. Slow (runs `gh`, may hit the GitHub API):
    /// compute once per account change, not per pane.
    public static func accountVars(settings: Settings, accounts: AccountStore) -> [String: String] {
        var env: [String: String] = [:]
        if let login = settings.activeGitHub, let token = accounts.githubToken(login) {
            let id = accounts.githubIdentity(login, token: token)
            env["GH_TOKEN"] = token
            if let name = id.name {
                env["GIT_AUTHOR_NAME"] = name
                env["GIT_COMMITTER_NAME"] = name
            }
            if let email = id.email {
                env["GIT_AUTHOR_EMAIL"] = email
                env["GIT_COMMITTER_EMAIL"] = email
            }
        }
        if let label = settings.activeVercel, let token = accounts.secrets.get(label) {
            env["VERCEL_TOKEN"] = token
        }
        return env
    }
}
