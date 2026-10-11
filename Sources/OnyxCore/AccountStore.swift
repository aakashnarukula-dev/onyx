import Foundation
import Security

public protocol SecretStore: Sendable {
    func get(_ label: String) -> String?
    func set(_ label: String, _ token: String) throws
    func delete(_ label: String)
}

/// Vercel tokens as generic passwords: service `com.onyx.vercel`, account = label.
public struct KeychainStore: SecretStore {
    let service = "com.onyx.vercel"

    public init() {}

    private func query(_ label: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: label]
    }

    public func get(_ label: String) -> String? {
        var q = query(label)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ label: String, _ token: String) throws {
        delete(label)
        var q = query(label)
        q[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func delete(_ label: String) {
        SecItemDelete(query(label) as CFDictionary)
    }
}

public typealias CommandRunner = @Sendable (String, [String], [String: String]?) -> (status: Int32, out: String, err: String)

/// GitHub accounts come from the `gh` CLI (which already supports several logins);
/// Vercel accounts are labelled tokens in a `SecretStore`.
public struct AccountStore: Sendable {
    public let paths: OnyxPaths
    public let secrets: SecretStore
    let run: CommandRunner
    let gh: String
    let vercel: String

    public init(paths: OnyxPaths, secrets: SecretStore, run: @escaping CommandRunner = { Shell.run($0, $1, env: $2) }) {
        self.paths = paths
        self.secrets = secrets
        self.run = run
        gh = Shell.which("gh")
        vercel = Shell.which("vercel")
    }

    /// Logins from `gh auth status` (it reports on stderr in some versions, stdout in others).
    public func githubLogins() -> [String] { ghStatus().map(\.login) }

    /// The login `gh` itself currently treats as active.
    public func githubActiveLogin() -> String? { ghStatus().first { $0.active }?.login }

    private func ghStatus() -> [(login: String, active: Bool)] {
        let r = run(gh, ["auth", "status"], nil)
        let marker = "Logged in to github.com account "
        var out: [(login: String, active: Bool)] = []
        for line in (r.out + "\n" + r.err).split(separator: "\n") {
            if let range = line.range(of: marker), let login = line[range.upperBound...].split(separator: " ").first {
                out.append((String(login), false))
            } else if line.contains("Active account: true"), !out.isEmpty {
                out[out.count - 1].active = true
            }
        }
        return out
    }

    public func githubToken(_ login: String) -> String? {
        let r = run(gh, ["auth", "token", "-u", login], nil)
        let t = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && !t.isEmpty ? t : nil
    }

    /// Settings override, else name/email from the GitHub API (noreply email when private).
    public func githubIdentity(_ login: String, token: String) -> GitHubIdentity {
        if let o = Settings.load(paths).identities[login] { return o }
        var env = ProcessInfo.processInfo.environment
        env["GH_TOKEN"] = token
        let r = run(gh, ["api", "user"], env)
        struct User: Decodable { let login: String; let id: Int; let name: String?; let email: String? }
        guard r.status == 0, let u = try? JSONDecoder().decode(User.self, from: Data(r.out.utf8)) else {
            return GitHubIdentity(login: login, name: login, email: nil)
        }
        let email = (u.email?.isEmpty == false ? u.email : nil) ?? "\(u.id)+\(u.login)@users.noreply.github.com"
        return GitHubIdentity(login: login, name: u.name?.isEmpty == false ? u.name : login, email: email)
    }

    /// Vercel username for a token, or nil if Vercel rejects it.
    public func validateVercel(token: String) -> String? {
        let r = run(vercel, ["whoami", "--token", token], nil)
        guard r.status == 0 else { return nil }
        return r.out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    }
}
