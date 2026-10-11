import Foundation

/// Commit identity for a GitHub login. Stored overrides win over what the API reports.
public struct GitHubIdentity: Codable, Equatable, Sendable {
    public var login: String
    public var name: String?
    public var email: String?

    public init(login: String, name: String?, email: String?) {
        self.login = login; self.name = name; self.email = email
    }
}

/// Non-secret app settings (`settings.json`). Tokens live in the Keychain.
public struct Settings: Codable, Equatable, Sendable {
    public var activeGitHub: String?
    public var activeVercel: String?
    public var vercelLabels: [String] = []
    public var identities: [String: GitHubIdentity] = [:]
    public var fontSize: Double = 13

    public init() {}

    public static func load(_ paths: OnyxPaths) -> Settings {
        guard let data = try? Data(contentsOf: paths.settings),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    public func save(_ paths: OnyxPaths) throws {
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: paths.settings, options: .atomic)
    }
}
