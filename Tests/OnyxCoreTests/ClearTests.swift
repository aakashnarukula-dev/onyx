import Testing
@testable import OnyxCore

struct ClearTests {
    /// ⌘K like Terminal.app: wipe scrollback locally, then Ctrl-L so the shell (or Claude) redraws.
    @Test func clearSequences() {
        #expect(TerminalClear.localSequence == "\u{1b}[H\u{1b}[2J\u{1b}[3J")
        #expect(TerminalClear.redrawKey == [0x0c])
    }
}
