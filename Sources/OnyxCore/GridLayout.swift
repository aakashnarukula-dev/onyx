import CoreGraphics

/// Where each terminal pane goes for a given pane count.
public enum GridLayout {
    public static let maxPanes = 6

    /// Panes per column, left to right. 1–2 panes sit side by side; from 3 on,
    /// columns hold 2 stacked panes and an odd last pane gets a full-height column.
    public static func columns(for n: Int) -> [Int] {
        let n = min(max(n, 0), maxPanes)
        if n <= 2 { return Array(repeating: 1, count: n) }
        var cols = Array(repeating: 2, count: n / 2)
        if n % 2 == 1 { cols.append(1) }
        return cols
    }

    /// Equal-split frames in pane order (column-major, top pane first in each
    /// column). AppKit coordinates: origin bottom-left.
    public static func frames(count: Int, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        frames(columns: columns(for: count), widths: nil, heights: nil, in: rect, gap: gap)
    }

    /// Frames using size fractions: `widths[c]` per column, `heights[c][r]` per row
    /// within column `c` (each list sums to 1). `nil` means equal split.
    public static func frames(columns cols: [Int], widths: [CGFloat]?, heights: [[CGFloat]]?,
                              in rect: CGRect, gap: CGFloat) -> [CGRect] {
        guard !cols.isEmpty else { return [] }
        let usableW = rect.width - gap * CGFloat(cols.count - 1)
        let w = widths ?? Array(repeating: 1 / CGFloat(cols.count), count: cols.count)
        var out: [CGRect] = []
        var x = rect.minX
        for (c, rows) in cols.enumerated() {
            let colW = (usableW * w[c]).rounded(.down)
            let colWidth = c == cols.count - 1 ? rect.maxX - x : colW
            let usableH = rect.height - gap * CGFloat(rows - 1)
            let h = heights?[c] ?? Array(repeating: 1 / CGFloat(rows), count: rows)
            var top = rect.maxY
            for r in 0..<rows {
                let rowH = r == rows - 1 ? top - rect.minY : (usableH * h[r]).rounded(.down)
                out.append(CGRect(x: x, y: top - rowH, width: colWidth, height: rowH))
                top -= rowH + gap
            }
            x += colWidth + gap
        }
        return out
    }
}
