import Foundation
import Testing
@testable import OnyxCore

struct SettingsTests {
    @Test func defaultFontIsElevenPoints() {
        #expect(Settings().fontSize == 11)
    }

    @Test func corruptFileGivesDefaults() throws {
        let paths = tempPaths()
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try "{not json".write(to: paths.settings, atomically: true, encoding: .utf8)
        #expect(Settings.load(paths) == Settings())
    }

    /// settings.json written by the earlier version (with account fields) still loads.
    @Test func olderFileStillLoads() throws {
        let paths = tempPaths()
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try #"{"activeGitHub":"x","fontSize":15,"vercelLabels":[]}"#.write(to: paths.settings, atomically: true, encoding: .utf8)
        #expect(Settings.load(paths).fontSize == 15)
    }

    @Test func roundTrip() throws {
        let paths = tempPaths()
        var s = Settings()
        s.fontSize = 16
        try s.save(paths)
        #expect(Settings.load(paths) == s)
    }
}
