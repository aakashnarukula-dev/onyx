import Foundation

/// Finds a plain http(s) URL at a terminal column, for ⌘-click (Terminal.app opens these).
public enum LinkFinder {
    /// `line` has one Character per terminal cell (empty cells as "\0").
    public static func url(in line: String, at col: Int) -> String? {
        let chars = Array(line)
        guard col >= 0, col < chars.count else { return nil }
        func isURLChar(_ c: Character) -> Bool {
            !c.isWhitespace && c != "\0" && !"\"'<>`|".contains(c)
        }
        guard isURLChar(chars[col]) else { return nil }
        var start = col, end = col
        while start > 0, isURLChar(chars[start - 1]) { start -= 1 }
        while end + 1 < chars.count, isURLChar(chars[end + 1]) { end += 1 }
        let word = String(chars[start...end])
        guard let r = word.range(of: "https?://", options: .regularExpression) else { return nil }
        // The click must land on the URL part of the word, not on text glued before it.
        let urlStart = start + word.distance(from: word.startIndex, to: r.lowerBound)
        guard col >= urlStart else { return nil }
        var url = String(word[r.lowerBound...])
        while let last = url.last, ".,;:!?)]}".contains(last) {
            if last == ")" && url.filter({ $0 == "(" }).count >= url.filter({ $0 == ")" }).count { break }
            url.removeLast()
        }
        guard col < urlStart + url.count else { return nil }
        return url.count > "https://".count ? url : nil
    }
}
