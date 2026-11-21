import Foundation
import Testing
@testable import OnyxCore

struct CodexSessionsTests {
    let first = "01a1f325-83ee-7cf0-8f86-3035e0d4af5d"
    let second = "01a1e8ee-079c-7492-94e6-92714624eb78"

    @Test func titlesIdentifyEachPaneWithoutUsingFolderOrRecency() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = dir.appendingPathComponent("shell_snapshots")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        for id in [first, second] {
            try Data().write(to: snapshots.appendingPathComponent("\(id).123.sh"))
        }
        let sessions = CodexSessions(configDir: dir)
        #expect(sessions.sessionID(fromTitle: first) == first)
        #expect(sessions.sessionID(fromTitle: String(first.prefix(27)) + "...") == first)
        #expect(sessions.sessionID(fromTitle: String(second.prefix(27)) + "…") == second)
        #expect(CodexSessions.title(String(first.prefix(27)) + "...", matches: first))
        #expect(!CodexSessions.title(String(first.prefix(27)) + "...", matches: second))
    }

    @Test func indexResolvesTitlesWithoutShellSnapshotsAndIgnoresBrokenLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("bad line\n{\"id\":\"\(first)\"}\n{\"id\":\"\(first)\"}\n".utf8)
            .write(to: dir.appendingPathComponent("session_index.jsonl"))
        #expect(CodexSessions(configDir: dir).sessionID(fromTitle: String(first.prefix(27)) + "...") == first)
    }

    @Test func ambiguousOrMissingPrefixesNeverChooseAnotherConversation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = dir.appendingPathComponent("shell_snapshots")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let sessions = CodexSessions(configDir: dir)
        let title = String(first.prefix(27)) + "..."
        #expect(sessions.sessionID(fromTitle: title) == nil)
        for id in [first, String(first.prefix(27)) + "000000000"] {
            try Data().write(to: snapshots.appendingPathComponent("\(id).sh"))
        }
        #expect(sessions.sessionID(fromTitle: title) == nil)
    }

    @Test func rejectsTaskNamesShortPrefixesAndShellText() {
        let sessions = CodexSessions(configDir: URL(fileURLWithPath: "/nonexistent"))
        for title in ["codex", "Fix login", "01a1...", "$(echo bad)", first + ";exit", "zzzzzzzz-zzzz-zzzz-zzzz-zzzzz..."] {
            #expect(!CodexSessions.isSessionTitle(title))
            #expect(sessions.sessionID(fromTitle: title) == nil)
        }
    }

    @Test func configDirFollowsCodexHome() {
        #expect(CodexSessions(env: ["CODEX_HOME": "/x/codex", "HOME": "/Users/me"]).configDir.path == "/x/codex")
        #expect(CodexSessions(env: ["HOME": "/Users/me"]).configDir.path == "/Users/me/.codex")
    }
}
