import AppKit
import OnyxCore

/// Tiles panes per `GridLayout` and lets the 1 pt gaps between them be dragged.
final class GridView: NSView {
    private(set) var panes: [PaneView] = []
    private var widths: [CGFloat] = []
    private var heights: [[CGFloat]] = []
    private var drag: Divider?
    private var lastPoint: CGPoint = .zero

    /// A draggable gap: between columns `index` and `index + 1`, or rows within `column`.
    private enum Divider: Equatable {
        case column(index: Int)
        case row(column: Int, index: Int)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.divider.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var columns: [Int] { GridLayout.columns(for: panes.count) }

    func setPanes(_ new: [PaneView]) {
        let added = new.filter { !panes.contains($0) }
        for p in panes where !new.contains(p) { p.removeFromSuperview() }
        panes = new
        added.forEach(addSubview)
        reflow()
    }

    /// Resets all dividers to equal sizes (after a pane is added or closed).
    func reflow() {
        let cols = columns
        widths = Array(repeating: 1 / CGFloat(max(cols.count, 1)), count: cols.count)
        heights = cols.map { Array(repeating: 1 / CGFloat($0), count: $0) }
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        let frames = GridLayout.frames(columns: columns, widths: widths, heights: heights, in: bounds, gap: Theme.gap)
        for (pane, f) in zip(panes, frames) { pane.frame = f }
    }

    // MARK: Divider dragging

    private var paneFrames: [CGRect] { panes.map(\.frame) }

    /// Panes of column `c` in pane order.
    private func columnRange(_ c: Int) -> Range<Int> {
        let start = columns.prefix(c).reduce(0, +)
        return start..<(start + columns[c])
    }

    private func divider(at p: CGPoint) -> Divider? {
        let slop: CGFloat = 3
        let cols = columns
        let frames = paneFrames
        for c in 0..<max(cols.count - 1, 0) {
            let x = frames[columnRange(c).lowerBound].maxX + Theme.gap / 2
            if abs(p.x - x) <= slop + Theme.gap / 2 { return .column(index: c) }
        }
        for c in 0..<cols.count where cols[c] > 1 {
            let r = columnRange(c)
            let top = frames[r.lowerBound]
            guard p.x >= top.minX, p.x <= top.maxX else { continue }
            let y = top.minY - Theme.gap / 2
            if abs(p.y - y) <= slop + Theme.gap / 2 { return .row(column: c, index: 0) }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if bounds.contains(local), divider(at: local) != nil { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        let cols = columns
        let frames = paneFrames
        guard frames.count == panes.count, !frames.isEmpty else { return }
        for c in 0..<max(cols.count - 1, 0) {
            let x = frames[columnRange(c).lowerBound].maxX
            addCursorRect(CGRect(x: x - 3, y: 0, width: Theme.gap + 6, height: bounds.height), cursor: .resizeLeftRight)
        }
        for c in 0..<cols.count where cols[c] > 1 {
            let top = frames[columnRange(c).lowerBound]
            addCursorRect(CGRect(x: top.minX, y: top.minY - Theme.gap - 3, width: top.width, height: Theme.gap + 6),
                          cursor: .resizeUpDown)
        }
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
        drag = divider(at: lastPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .column(let i):
            let usable = bounds.width - Theme.gap * CGFloat(widths.count - 1)
            widths = GridLayout.drag(fractions: widths, divider: i, by: p.x - lastPoint.x, total: usable, min: Theme.minPane.width)
        case .row(let c, let i):
            let usable = bounds.height - Theme.gap * CGFloat(heights[c].count - 1)
            // AppKit y grows upward; row 0 is the top pane, so dragging up shrinks it.
            heights[c] = GridLayout.drag(fractions: heights[c], divider: i, by: lastPoint.y - p.y, total: usable, min: Theme.minPane.height)
        }
        lastPoint = p
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        window?.invalidateCursorRects(for: self)
    }

    /// The pane next to `pane` in a direction, by nearest frame centre.
    func neighbour(of pane: PaneView, dx: CGFloat, dy: CGFloat) -> PaneView? {
        let c = CGPoint(x: pane.frame.midX, y: pane.frame.midY)
        return panes.filter { $0 !== pane }.filter {
            let d = CGPoint(x: $0.frame.midX - c.x, y: $0.frame.midY - c.y)
            return dx != 0 ? d.x * dx > 1 : d.y * dy > 1
        }.min { a, b in
            hypot(a.frame.midX - c.x, a.frame.midY - c.y) < hypot(b.frame.midX - c.x, b.frame.midY - c.y)
        }
    }
}
