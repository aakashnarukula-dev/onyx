import Foundation
import Testing
@testable import OnyxCore

final class MemorySecrets: SecretStore, @unchecked Sendable {
    var items: [String: String] = [:]
    func get(_ label: String) -> String? { items[label] }
    func set(_ label: String, _ token: String) throws { items[label] = token }
    func delete(_ label: String) { items[label] = nil }
}

/// Fake CLI runner keyed by "path arg1 arg2...".
final class FakeRunner: @unchecked Sendable {
    var replies: [String: (Int32, String, String)] = [:]
    var calls: [String] = []
    var envs: [[String: String]?] = []
    func run(_ path: String, _ args: [String], _ env: [String: String]?) -> (status: Int32, out: String, err: String) {
        let key = ([URL(fileURLWithPath: path).lastPathComponent] + args).joined(separator: " ")
        calls.append(key)
        envs.append(env)
        let r = replies[key] ?? (1, "", "no fake for \(key)")
        return (r.0, r.1, r.2)
    }
}

let ghStatus = """
github.com
  ✓ Logged in to github.com account foo (keyring)
  - Active account: true
  - Token: gho_***

  ✓ Logged in to github.com account bar (keyring)
  - Active account: false
"""

struct AccountStoreTests {
    func store(_ runner: FakeRunner, paths: OnyxPaths = tempPaths()) -> AccountStore {
        AccountStore(paths: paths, secrets: MemorySecrets(), run: runner.run)
    }

    @Test func parsesGhStatusMultipleAccounts() {
        let r = FakeRunner()
        r.replies["gh auth status"] = (0, "", ghStatus) // gh prints status to stderr
        #expect(store(r).githubLogins() == ["foo", "bar"])
    }

    @Test func activeLoginFromGhStatus() {
        let r = FakeRunner()
        r.replies["gh auth status"] = (0, ghStatus.replacingOccurrences(of: "true", with: "X").replacingOccurrences(of: "false", with: "true"), "")
        #expect(store(r).githubActiveLogin() == "bar")
    }

    @Test func tokenFailureIsNil() {
        let r = FakeRunner()
        r.replies["gh auth token -u foo"] = (1, "", "no token")
        #expect(store(r).githubToken("foo") == nil)
    }

    @Test func identityFromApiFallsBackToNoreply() {
        let r = FakeRunner()
        r.replies["gh api user"] = (0, #"{"login":"foo","id":42,"name":"Foo Bar","email":null}"#, "")
        let id = store(r).githubIdentity("foo", token: "t")
        #expect(id == GitHubIdentity(login: "foo", name: "Foo Bar", email: "42+foo@users.noreply.github.com"))
    }

    @Test func identityOverrideSkipsApi() throws {
        let paths = tempPaths()
        var s = Settings()
        s.identities["gyftalala"] = GitHubIdentity(login: "gyftalala", name: "Gyftalala", email: "mail@gyftalala.com")
        try s.save(paths)
        let r = FakeRunner()
        let id = store(r, paths: paths).githubIdentity("gyftalala", token: "t")
        #expect(id.email == "mail@gyftalala.com")
        #expect(r.calls.isEmpty)
    }

    @Test func validateVercel() {
        let r = FakeRunner()
        r.replies["vercel whoami"] = (0, "Vercel CLI 59\nfoo-user", "")
        #expect(store(r).validateVercel(token: "good") == "foo-user")
        // The token travels in the environment, never on argv (visible in `ps`).
        #expect(r.envs.last??["VERCEL_TOKEN"] == "good")
        #expect(!r.calls.contains { $0.contains("good") })
    }

    @Test func settingsCorruptFileDefaults() throws {
        let paths = tempPaths()
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try "{not json".write(to: paths.settings, atomically: true, encoding: .utf8)
        #expect(Settings.load(paths) == Settings())
    }

    @Test func settingsRoundTrip() throws {
        let paths = tempPaths()
        var s = Settings()
        s.activeGitHub = "foo"; s.activeVercel = "work"; s.vercelLabels = ["work"]; s.fontSize = 15
        try s.save(paths)
        #expect(Settings.load(paths) == s)
    }
}
