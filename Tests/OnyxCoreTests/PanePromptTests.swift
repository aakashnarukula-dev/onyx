import Foundation
import Testing
@testable import OnyxCore

struct PanePromptTests {
    @Test func containsTheRules() {
        for needle in ["onyx-pane claim", "USE_WORKTREE", "onyx-pane push", "never `git push --force`",
                       "CONFLICT", "onyx-pane release", "CLAUDE.md"] {
            #expect(PanePrompt.text.contains(needle), "missing \(needle)")
        }
    }

    @Test func writeRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try PanePrompt.write(to: dir)
        #expect(url.lastPathComponent == "pane-prompt.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == PanePrompt.text)
    }
}
