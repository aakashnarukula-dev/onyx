import AppKit
import OnyxCore

/// Tiles panes per `GridLayout`, lets the gaps between them be dragged, and lets a pane be moved by its header.
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
        layer?.backgroundColor = Theme.background.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var columns: [Int] { GridLayout.columns(for: panes.count) }

    /// Called with the new pane order after the user drags a pane to another place.
    var onReorder: (([PaneView]) -> Void)?

    func setPanes(_ new: [PaneView]) {
        cancelMove()  // a pane added or closed mid-drag ends the drag
        let added = new.filter { !panes.contains($0) }
        for p in panes where !new.contains(p) { p.removeFromSuperview() }
        panes = new
        for p in added {
            addSubview(p)
            p.onHeaderDrag = { [weak self] pane, phase, event in self?.headerDrag(pane, phase, event) }
        }
        reflow()
    }

    /// Resets all dividers to equal sizes (after a pane is added or closed).
    func reflow() {
        drag = nil  // a pane closing mid-drag must not leave a divider index into the old layout
        let cols = columns
        widths = Array(repeating: 1 / CGFloat(max(cols.count, 1)), count: cols.count)
        heights = cols.map { Array(repeating: 1 / CGFloat($0), count: $0) }
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    /// Where the panes go: the view less the margin around them.
    private var area: CGRect { bounds.insetBy(dx: Theme.margin, dy: Theme.margin) }

    override func layout() {
        super.layout()
        guard move == nil else { return }  // a pane drag places the panes itself
        let frames = GridLayout.frames(columns: columns, widths: widths, heights: heights, in: area, gap: Theme.gap)
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
            guard i + 1 < widths.count else { self.drag = nil; return }
            let usable = area.width - Theme.gap * CGFloat(widths.count - 1)
            widths = GridLayout.drag(fractions: widths, divider: i, by: p.x - lastPoint.x, total: usable, min: Theme.minPane.width)
        case .row(let c, let i):
            guard c < heights.count, i + 1 < heights[c].count else { self.drag = nil; return }
            let usable = area.height - Theme.gap * CGFloat(heights[c].count - 1)
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

    // MARK: Moving panes

    /// A pane being dragged by its header. It follows the cursor; the others slide into the places
    /// they would take if it were dropped there, and an outline marks where it will land.
    private struct Move {
        let pane: PaneView
        let from: Int
        var to: Int
        let slots: [CGRect]
        let grab: CGPoint  // cursor offset inside the dragged pane
        let placeholder: NSView
        let token: Int
        var dropping = false  // released; settling into place
    }

    private var move: Move?
    private var moveCount = 0

    private func headerDrag(_ pane: PaneView, _ phase: PaneHeader.DragPhase, _ event: NSEvent) {
        // Only the pane being moved steers the move; a grab while another is settling is ignored.
        if let m = move, m.pane !== pane || m.dropping { return }
        let p = convert(event.locationInWindow, from: nil)
        switch phase {
        case .began: beginMove(pane, at: p)
        case .moved: updateMove(to: p)
        case .ended: endMove()
        }
    }

    private func beginMove(_ pane: PaneView, at p: CGPoint) {
        guard move == nil, panes.count > 1, let from = panes.firstIndex(of: pane) else { return }
        let placeholder = PassThroughView(frame: pane.frame)
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = Theme.cornerRadius
        placeholder.layer?.borderWidth = 1.5
        placeholder.layer?.borderColor = Theme.accent.withAlphaComponent(0.6).cgColor
        placeholder.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.05).cgColor
        addSubview(placeholder, positioned: .below, relativeTo: nil)
        addSubview(pane, positioned: .above, relativeTo: nil)  // ride above the others
        pane.layer?.shadowColor = NSColor.black.cgColor
        pane.layer?.shadowOpacity = 0.7
        pane.layer?.shadowRadius = 16
        pane.alphaValue = 0.94
        moveCount += 1
        move = Move(pane: pane, from: from, to: from, slots: panes.map(\.frame),
                    grab: CGPoint(x: p.x - pane.frame.minX, y: p.y - pane.frame.minY), placeholder: placeholder,
                    token: moveCount)
        NSCursor.closedHand.push()
    }

    private func updateMove(to p: CGPoint) {
        guard var m = move else { return }
        // Moving (not resizing) the dragged terminal: nothing is redrawn, the program sees no resize.
        m.pane.setFrameOrigin(CGPoint(x: p.x - m.grab.x, y: p.y - m.grab.y))
        guard let to = GridLayout.slot(at: p, in: m.slots), to != m.to else { return }
        m.to = to
        move = m
        let order = GridLayout.moving(panes, from: m.from, to: to)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            for (i, pane) in order.enumerated() {
                let slot = m.slots[i]
                if pane === m.pane { m.placeholder.animator().frame = slot; continue }
                // Take the new size at once (one resize for the program), then glide into place.
                if pane.frame.size != slot.size { pane.setFrameSize(slot.size) }
                pane.animator().setFrameOrigin(slot.origin)
            }
        }
    }

    private func endMove() {
        guard var m = move, !m.dropping else { return }
        m.dropping = true
        move = m
        let order = GridLayout.moving(panes, from: m.from, to: m.to)
        let slot = m.slots[m.to]
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if m.pane.frame.size != slot.size { m.pane.setFrameSize(slot.size) }
            m.pane.animator().setFrameOrigin(slot.origin)
            m.pane.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.move?.token == m.token else { return }  // not cancelled meanwhile
                self.cancelMove()
                // Same count, so the divider sizes stay with their places; panes take the size of their new place.
                self.panes = order
                self.needsLayout = true
                self.layoutSubtreeIfNeeded()
                self.window?.invalidateCursorRects(for: self)
                self.onReorder?(order)
                m.pane.focus()
            }
        })
    }

    /// Ends a drag: the dragged pane's lift goes away and the grid lays out its current order.
    private func cancelMove() {
        guard let m = move else { return }
        move = nil
        m.placeholder.removeFromSuperview()
        m.pane.layer?.shadowOpacity = 0
        m.pane.alphaValue = 1
        NSCursor.pop()
        needsLayout = true
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

/// Shows content but never takes the mouse.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
