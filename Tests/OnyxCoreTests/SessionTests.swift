import Foundation
import Testing
@testable import OnyxCore

struct SessionStateTests {
    @Test func savesAndLoadsWindowsAndPanes() throws {
        let paths = tempPaths()
        let state = SessionState(windows: [
            .init(frame: [10, 20, 1280, 820], panes: [
                .init(cwd: "/Users/me/Developer", claudeSession: "2cba7231-0ccd-4566-9071-6e62a3c89441"),
                .init(cwd: "/Users/me/Developer/app", claudeSession: nil),
            ]),
        ])
        #expect(try state.save(paths) == true)
        #expect(SessionState.load(paths) == state)
    }

    @Test func unchangedStateIsNotRewritten() throws {
        let paths = tempPaths()
        let state = SessionState(windows: [.init(frame: [0, 0, 800, 600], panes: [.init(cwd: "/tmp", claudeSession: nil)])])
        #expect(try state.save(paths) == true)
        #expect(try state.save(paths) == false)
    }

    @Test func missingOrBrokenFileMeansNothingToRestore() throws {
        let paths = tempPaths()
        #expect(SessionState.load(paths) == nil)
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: paths.session)
        #expect(SessionState.load(paths) == nil)
    }
}

struct ClaudeSessionsTests {
    /// A fake ~/.claude with one running session record and one transcript.
    func fakeClaudeDir(pid: Int32, id: String, cwd: String, transcript: Bool, status: String = "idle") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString)")
        let sessions = dir.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let record = #"{"pid": \#(pid), "sessionId": "\#(id)", "cwd": "\#(cwd)", "kind": "interactive", "status": "\#(status)"}"#
        try Data(record.utf8).write(to: sessions.appendingPathComponent("\(pid).json"))
        if transcript {
            let project = dir.appendingPathComponent("projects/-Users-me-Developer")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("{}\n".utf8).write(to: project.appendingPathComponent("\(id).jsonl"))
        }
        return dir
    }

    let id = "2cba7231-0ccd-4566-9071-6e62a3c89441"

    @Test func readsTheSessionOfARunningClaude() throws {
        let dir = try fakeClaudeDir(pid: 4242, id: id, cwd: "/Users/me/Developer", transcript: true)
        let s = ClaudeSessions(configDir: dir).running(pid: 4242)
        #expect(s == .init(id: id, cwd: "/Users/me/Developer", working: false))
        #expect(ClaudeSessions(configDir: dir).running(pid: 4243) == nil)
    }

    @Test func claudeIsWorkingWhileBusyOrWaitingForAnAnswer() throws {
        for (status, working) in [("busy", true), ("waiting", true), ("idle", false)] {
            let dir = try fakeClaudeDir(pid: 9, id: id, cwd: "/tmp", transcript: false, status: status)
            #expect(ClaudeSessions(configDir: dir).running(pid: 9)?.working == working)
        }
    }

    @Test func savedStateKnowsWhetherAnythingIsWorthReopening() {
        let empty = SessionState(windows: [.init(frame: [0, 0, 1, 1], panes: [.init(cwd: "/tmp", claudeSession: nil)])])
        #expect(empty.conversations(where: { _ in true }).isEmpty)
        let one = SessionState(windows: [.init(frame: [0, 0, 1, 1], panes: [
            .init(cwd: "/tmp", claudeSession: id), .init(cwd: "/tmp", claudeSession: "0badc0de-0000-0000-0000-000000000000"),
        ])])
        #expect(one.conversations(where: { $0 == id }) == [id])
    }

    @Test func rejectsARecordForAnotherPidOrAnOddId() throws {
        let dir = try fakeClaudeDir(pid: 4242, id: "x; rm -rf ~", cwd: "/tmp", transcript: false)
        #expect(ClaudeSessions(configDir: dir).running(pid: 4242) == nil)
        let other = try fakeClaudeDir(pid: 7, id: id, cwd: "/tmp", transcript: false)
        try FileManager.default.moveItem(at: other.appendingPathComponent("sessions/7.json"),
                                         to: other.appendingPathComponent("sessions/8.json"))
        #expect(ClaudeSessions(configDir: other).running(pid: 8) == nil)
    }

    @Test func resumesOnlyConversationsThatWereSaved() throws {
        let saved = try fakeClaudeDir(pid: 1, id: id, cwd: "/tmp", transcript: true)
        #expect(ClaudeSessions(configDir: saved).hasTranscript(id: id))
        let empty = try fakeClaudeDir(pid: 1, id: id, cwd: "/tmp", transcript: false)
        #expect(!ClaudeSessions(configDir: empty).hasTranscript(id: id))
    }

    @Test func resumeCommandKeepsAutoMode() {
        #expect(ClaudeSessions.resumeCommand(id: id) == "claude --resume \(id) --permission-mode auto")
    }

    @Test func configDirFollowsClaudeConfigDir() {
        #expect(ClaudeSessions(env: ["CLAUDE_CONFIG_DIR": "/x/claude", "HOME": "/Users/me"]).configDir.path == "/x/claude")
        #expect(ClaudeSessions(env: ["HOME": "/Users/me"]).configDir.path == "/Users/me/.claude")
    }
}

struct AssistantSessionTests {
    @Test func mixedProvidersRoundTrip() throws {
        let state = SessionState(windows: [.init(frame: [0, 0, 800, 600], panes: [
            .init(cwd: "/tmp", claudeSession: nil, assistant: .claude),
            .init(cwd: "/tmp", claudeSession: nil, assistant: .codex)
        ])])
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SessionState.self, from: data) == state)
    }

    @Test func legacyPaneStillLoads() throws {
        let data = Data(#"{"cwd":"/tmp"}"#.utf8)
        let pane = try JSONDecoder().decode(SessionState.Pane.self, from: data)
        #expect(pane.assistant == nil)
        #expect(pane.claudeSession == nil)
    }
}
