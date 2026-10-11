import Foundation

/// App settings (`settings.json`): just the font size.
public struct Settings: Codable, Equatable, Sendable {
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
