import Foundation

public enum Assistant: String, Codable, CaseIterable, Sendable {
    case claude, codex

    public var title: String { self == .claude ? "Claude" : "Codex (ChatGPT)" }
    public var command: String { self == .claude ? PaneEnv.claudeCommand : "codex" }
}

/// App settings (`settings.json`).
public struct Settings: Codable, Equatable, Sendable {
    public var fontSize: Double = 14
    public var assistant: Assistant = .claude

    private enum CodingKeys: String, CodingKey { case fontSize, assistant }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 14
        assistant = try values.decodeIfPresent(Assistant.self, forKey: .assistant) ?? .claude
    }

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
