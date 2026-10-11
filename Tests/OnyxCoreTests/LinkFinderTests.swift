import Testing
@testable import OnyxCore

struct LinkFinderTests {
    let line = "Open https://claude.ai/oauth?code=abc&x=1 to sign in"

    @Test func findsURLUnderColumn() {
        #expect(LinkFinder.url(in: line, at: 5) == "https://claude.ai/oauth?code=abc&x=1")
        #expect(LinkFinder.url(in: line, at: 30) == "https://claude.ai/oauth?code=abc&x=1")
    }

    @Test func nothingOutsideURL() {
        #expect(LinkFinder.url(in: line, at: 2) == nil)
        #expect(LinkFinder.url(in: line, at: 45) == nil)
        #expect(LinkFinder.url(in: line, at: 500) == nil)
    }

    @Test func trimsTrailingPunctuationAndBrackets() {
        #expect(LinkFinder.url(in: "see (https://x.dev/a).", at: 8) == "https://x.dev/a")
        #expect(LinkFinder.url(in: "go to http://localhost:5500/, then", at: 10) == "http://localhost:5500/")
    }

    @Test func nullCellsEndTheURL() {
        #expect(LinkFinder.url(in: "https://a.io\0\0\0text", at: 3) == "https://a.io")
    }
}
