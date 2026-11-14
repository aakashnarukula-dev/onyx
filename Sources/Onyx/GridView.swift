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

    func setPanes(_ new: [PaneView], animated: Bool = false) {
        clearInsertion(restoring: false)
        cancelMove()  // a pane added or closed mid-drag ends the drag
        let added = new.filter { !panes.contains($0) }
        for p in panes where !new.contains(p) { p.removeFromSuperview() }
        panes = new
        for p in added {
            addSubview(p)
            p.onHeaderDrag = { [weak self] pane, phase, event in self?.headerDrag(pane, phase, event) }
        }
        reflow()
        if animated {
            needsLayout = false
            let frames = GridLayout.frames(columns: columns, widths: widths, heights: heights, in: area, gap: Theme.gap)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (pane, frame) in zip(panes, frames) {
                    pane.setFrameSize(frame.size)
                    if added.contains(pane) { pane.frame = frame }
                    else { pane.animator().setFrameOrigin(frame.origin) }
                }
            }
        }
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
        guard move == nil, insertionPreview == nil else { return }  // drag previews place panes themselves
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
        let windowAlpha: CGFloat
        var floating = false
        var dropping = false  // released; settling into place
    }

    private var move: Move?
    private var moveCount = 0
    private var preview: PaneDragPreview?
    private var escapeMonitor: Any?

    /// The host highlights the frontmost eligible destination, even when it overlaps this window.
    var onDragLocation: ((NSPoint) -> Bool)?
    var onDragFinished: (() -> Void)?
    var onDropFrame: ((PaneView, NSPoint) -> NSRect?)?

    private func headerDrag(_ pane: PaneView, _ phase: PaneHeader.DragPhase, _ event: NSEvent) {
        // Only the pane being moved steers the move; a grab while another is settling is ignored.
        if let m = move, m.pane !== pane || m.dropping { return }
        let p = convert(event.locationInWindow, from: nil)
        switch phase {
        case .began: beginMove(pane, at: p)
        case .moved: updateMove(to: p)
        case .ended:
            if let w = window, let m = move, m.floating, !m.dropping {
                let screen = w.convertPoint(toScreen: event.locationInWindow)
                move?.dropping = true
                let finish: @MainActor @Sendable () -> Void = { [weak self] in
                    guard let self, self.move?.token == m.token else { return }
                    // Keep a hidden one-pane source transparent until the host selects the
                    // destination. Restoring it first would obscure the window beneath it.
                    self.cancelMove(clearDestination: false, restoreWindow: false)
                    self.onTearOff?(m.pane, screen)
                    self.window?.alphaValue = m.windowAlpha
                }
                if let frame = onDropFrame?(m.pane, screen), let preview {
                    preview.settle(into: frame, completion: finish)
                } else { finish() }
                return
            }
            endMove()
        }
    }

    /// Released pane and screen position. The host either joins a window or creates one.
    var onTearOff: ((PaneView, NSPoint) -> Void)?

    private func beginMove(_ pane: PaneView, at p: CGPoint) {
        guard move == nil, let from = panes.firstIndex(of: pane) else { return }
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
                    token: moveCount, windowAlpha: window?.alphaValue ?? 1)
        NSCursor.closedHand.push()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancelMove()
            return nil
        }
    }

    private func updateMove(to p: CGPoint) {
        guard var m = move, !m.dropping, let window else { return }
        let screen = window.convertPoint(toScreen: convert(p, to: nil))
        let joining = onDragLocation?(screen) ?? false
        // Like a tab strip, the original headers are the rearranging / return zone.
        // Pulling away vertically also tears off in a maximized or full-screen window.
        let headerSlots = m.slots.indices.filter { index in
            let slot = m.slots[index]
            return CGRect(x: slot.minX, y: slot.maxY - Theme.headerHeight,
                          width: slot.width, height: Theme.headerHeight).insetBy(dx: -8, dy: -18).contains(p)
        }
        if joining || headerSlots.isEmpty {
            if !m.floating {
                preview = PaneDragPreview(pane: m.pane, screenFrame: window.convertToScreen(convert(m.pane.frame, to: nil)))
                m.pane.alphaValue = 0
                m.placeholder.alphaValue = 0
                // A window losing its only pane travels as the preview, without an empty duplicate.
                if panes.count == 1 { window.alphaValue = 0 }
                let others = panes.filter { $0 !== m.pane }
                let frames = GridLayout.frames(count: others.count, in: area, gap: Theme.gap)
                animate(others, into: frames)
                m.floating = true
            }
            move = m
            preview?.follow(screen, grab: m.grab, joining: joining)
            return
        }
        let returning = m.floating
        if returning {
            preview?.close()
            preview = nil
            m.floating = false
            m.pane.alphaValue = 0.94
            m.placeholder.alphaValue = 1
            window.alphaValue = m.windowAlpha
            move = m
        }
        // Moving (not resizing) the dragged terminal: nothing is redrawn, the program sees no resize.
        m.pane.setFrameOrigin(CGPoint(x: p.x - m.grab.x, y: p.y - m.grab.y))
        let to = headerSlots.min {
            hypot(m.slots[$0].midX - p.x, m.slots[$0].maxY - p.y) < hypot(m.slots[$1].midX - p.x, m.slots[$1].maxY - p.y)
        } ?? m.from
        guard to != m.to || returning else { return }
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
    private func cancelMove(clearDestination: Bool = true, restoreWindow: Bool = true) {
        guard let m = move else { return }
        move = nil
        preview?.close()
        preview = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        if clearDestination { onDragFinished?() }
        m.placeholder.removeFromSuperview()
        m.pane.layer?.shadowOpacity = 0
        m.pane.alphaValue = 1
        if restoreWindow { window?.alphaValue = m.windowAlpha }
        NSCursor.pop()
        needsLayout = true
    }

    private var insertionPreview: NSView?
    private(set) var insertionIndex: Int?

    private func animate(_ views: [PaneView], into frames: [CGRect]) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (pane, frame) in zip(views, frames) {
                pane.setFrameSize(frame.size)
                pane.animator().setFrameOrigin(frame.origin)
            }
        }
    }

    /// Slides neighboring panes aside to open the incoming pane's slot.
    func showInsertion(at point: CGPoint) -> CGRect {
        let slots = GridLayout.frames(count: panes.count + 1, in: area, gap: Theme.gap)
        let index = GridLayout.slot(at: point, in: slots) ?? slots.indices.min {
            hypot(slots[$0].midX - point.x, slots[$0].midY - point.y) < hypot(slots[$1].midX - point.x, slots[$1].midY - point.y)
        } ?? 0
        let frame = slots[index]
        guard insertionIndex != index || insertionPreview?.frame != frame else { return frame }
        if insertionPreview == nil {
            let view = PassThroughView(frame: frame)
            view.wantsLayer = true
            view.layer?.cornerRadius = Theme.cornerRadius
            view.layer?.borderWidth = 2
            view.layer?.borderColor = Theme.accent.cgColor
            view.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
            addSubview(view, positioned: .above, relativeTo: nil)
            insertionPreview = view
            view.alphaValue = 0
        }
        insertionIndex = index
        animate(panes, into: slots.enumerated().filter { $0.offset != index }.map(\.element))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            insertionPreview?.animator().frame = frame
            insertionPreview?.animator().alphaValue = 1
        }
        return frame
    }

    func clearInsertion(restoring: Bool = true) {
        guard insertionPreview != nil else { return }
        insertionPreview?.removeFromSuperview()
        insertionPreview = nil
        insertionIndex = nil
        if restoring {
            let frames = GridLayout.frames(columns: columns, widths: widths, heights: heights, in: area, gap: Theme.gap)
            animate(panes, into: frames)
        }
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

/// A window-level drag image: it follows the pointer outside the source window without
/// reparenting the live terminal or interrupting AppKit's original mouse tracking.
private final class PaneDragPreview: NSPanel {
    private let scale: CGFloat
    private var joining = false

    init(pane: PaneView, screenFrame: NSRect) {
        scale = min(1, 720 / screenFrame.width, 480 / screenFrame.height)
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let image = NSImageView(frame: NSRect(origin: .zero, size: screenFrame.size))
        image.image = Self.snapshot(pane)
        image.imageScaling = .scaleAxesIndependently
        image.wantsLayer = true
        image.layer?.backgroundColor = Theme.background.cgColor
        image.layer?.cornerRadius = Theme.cornerRadius
        image.layer?.masksToBounds = true
        contentView = image
        setContentSize(CGSize(width: screenFrame.width * scale, height: screenFrame.height * scale))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0.94
        }
    }

    func follow(_ point: NSPoint, grab: CGPoint, joining: Bool) {
        setFrameOrigin(CGPoint(x: point.x - grab.x * scale, y: point.y - grab.y * scale))
        if joining != self.joining {
            self.joining = joining
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().alphaValue = joining ? 0.75 : 0.94
            }
        }
    }

    func settle(into frame: NSRect, completion: @escaping @MainActor @Sendable () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
            animator().alphaValue = 1
        }, completionHandler: {
            MainActor.assumeIsolated { completion() }
        })
    }

    private static func snapshot(_ pane: PaneView) -> NSImage? {
        guard let rep = pane.bitmapImageRepForCachingDisplay(in: pane.bounds) else { return nil }
        pane.cacheDisplay(in: pane.bounds, to: rep)
        guard let base = rep.cgImage,
              let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        context.setFillColor(Theme.background.cgColor)
        context.fill(rect)
        context.draw(base, in: rect)
        // SwiftTerm's own capture keeps terminal text upright, unlike the parent capture.
        let terminal = pane.terminal
        if let text = terminal.bitmapImageRepForCachingDisplay(in: terminal.bounds) {
            terminal.cacheDisplay(in: terminal.bounds, to: text)
            if let image = text.cgImage {
                let scale = CGFloat(base.width) / pane.bounds.width
                let frame = terminal.convert(terminal.bounds, to: pane)
                let target = CGRect(x: frame.minX * scale, y: (pane.bounds.height - frame.maxY) * scale,
                                    width: frame.width * scale, height: frame.height * scale)
                context.fill(target)
                context.draw(image, in: target)
            }
        }
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: pane.bounds.size)
    }
}
