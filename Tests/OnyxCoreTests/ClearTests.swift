import Testing
@testable import OnyxCore

struct ClearTests {
    /// ⌘K like Terminal.app: wipe scrollback locally, then Ctrl-L so the shell (or Claude) redraws.
    @Test func clearSequences() {
        #expect(TerminalClear.localSequence == "\u{1b}[H\u{1b}[2J\u{1b}[3J")
        #expect(TerminalClear.redrawKey == [0x0c])
    }
}

struct DropTests {
    @Test func pathsAreEscapedLikeTerminalApp() {
        #expect(DroppedFiles.text(for: ["/Users/me/Desktop/Screen Recording 2026-10-12 at 12.36.21 AM.mov"])
                == #"/Users/me/Desktop/Screen\ Recording\ 2026-10-12\ at\ 12.36.21\ AM.mov "#)
    }

    @Test func shellSpecialCharactersAreEscaped() {
        #expect(DroppedFiles.text(for: [#"/tmp/a'b"c$d&e(f).png"#]) == #"/tmp/a\'b\"c\$d\&e\(f\).png "#)
    }

    @Test func severalFilesAreSpaceSeparated() {
        #expect(DroppedFiles.text(for: ["/a/x.png", "/b/y z.pdf"]) == #"/a/x.png /b/y\ z.pdf "#)
    }

    @Test func plainPathsAndUnicodeStayAsTheyAre() {
        #expect(DroppedFiles.text(for: ["/Users/me/हिन्दी/photo_1-2.jpg"]) == "/Users/me/हिन्दी/photo_1-2.jpg ")
    }
}

struct PaneTitleTests {
    @Test func claudeStatusSymbolIsDropped() {
        #expect(PaneTitle.plain("✳ Admin panel chat doubt") == "Admin panel chat doubt")
        #expect(PaneTitle.plain("◑ Contributor name mismatch") == "Contributor name mismatch")
        #expect(PaneTitle.plain("⠂ Fixing tests") == "Fixing tests")
    }

    @Test func ordinaryTitlesStayAsTheyAre() {
        #expect(PaneTitle.plain("~/Developer/onyx") == "~/Developer/onyx")
        #expect(PaneTitle.plain("vim") == "vim")
        #expect(PaneTitle.plain("") == "")
    }
}
