import AppKit
import OnyxCore

/// Window that reports which pane's terminal got keyboard focus.
final class OnyxWindow: NSWindow {
    var onFirstResponder: ((NSResponder?) -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let ok = super.makeFirstResponder(responder)
        if ok { onFirstResponder?(responder) }
        return ok
    }
}

/// Top strip: room for the traffic lights, the `+` button and the accounts chip.
final class TopBar: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) }
    }
}

@MainActor protocol WindowControllerDelegate: AnyObject {
    func makePane(for controller: WindowController) -> PaneView
    func windowControllerDidClose(_ controller: WindowController)
}

/// One Onyx window holding up to `GridLayout.maxPanes` independent terminals.
final class WindowController: NSWindowController, NSWindowDelegate, PaneViewDelegate {
    weak var host: WindowControllerDelegate?
    let topBar = TopBar()
    let grid = GridView()
    private let addButton = HoverButton(title: "+")
    private let countLabel = NSTextField(labelWithString: "")
    private(set) var panes: [PaneView] = []
    private(set) weak var focused: PaneView?
    /// Right-hand slot in the top bar (accounts chip).
    var accessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let accessory { topBar.addSubview(accessory) }
            layoutTopBar()
        }
    }

    var canAddPane: Bool { panes.count < GridLayout.maxPanes }

    init(owner: WindowControllerDelegate, frame: NSRect) {
        self.host = owner
        let window = OnyxWindow(contentRect: frame,
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
        window.title = "Onyx"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = CGSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.onFirstResponder = { [weak self] r in self?.responderChanged(r) }

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.background.cgColor
        window.contentView = content
        content.addSubview(grid)
        content.addSubview(topBar)

        addButton.fontSize = 17
        addButton.toolTip = "New terminal (⌘N)"
        addButton.target = self
        addButton.action = #selector(addTapped)
        topBar.addSubview(addButton)
        countLabel.font = Theme.ui(11, .medium)
        countLabel.textColor = Theme.muted
        topBar.addSubview(countLabel)

        NotificationCenter.default.addObserver(self, selector: #selector(layoutAll),
                                               name: NSView.frameDidChangeNotification, object: content)
        content.postsFrameChangedNotifications = true
        layoutAll()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func layoutAll() {
        guard let content = window?.contentView else { return }
        let b = content.bounds
        topBar.frame = CGRect(x: 0, y: b.height - Theme.topBarHeight, width: b.width, height: Theme.topBarHeight)
        grid.frame = CGRect(x: 0, y: 0, width: b.width, height: b.height - Theme.topBarHeight)
        layoutTopBar()
    }

    func relayoutTopBar() { layoutTopBar() }

    private func layoutTopBar() {
        let h = Theme.topBarHeight
        addButton.frame = CGRect(x: 78, y: (h - 22) / 2, width: 24, height: 22)
        countLabel.sizeToFit()
        countLabel.frame.origin = CGPoint(x: addButton.frame.maxX + 6, y: (h - countLabel.frame.height) / 2)
        if let accessory {
            let s = accessory.fittingSize
            accessory.frame = CGRect(x: topBar.bounds.width - s.width - 10, y: (h - s.height) / 2, width: s.width, height: s.height)
        }
    }

    @objc private func addTapped() {
        (NSApp.delegate as? AppDelegate)?.newPane(nil)
    }

    // MARK: Panes

    func addPane() {
        guard canAddPane, let host else { return }
        let pane = host.makePane(for: self)
        pane.delegate = self
        panes.append(pane)
        grid.setPanes(panes)
        updateCount()
        grid.layoutSubtreeIfNeeded()
        pane.focus()
    }

    func close(_ pane: PaneView) {
        guard let i = panes.firstIndex(of: pane) else { return }
        pane.shutdown()
        panes.remove(at: i)
        if panes.isEmpty {
            window?.close()
            return
        }
        grid.setPanes(panes)
        updateCount()
        if focused === pane || focused == nil { panes[min(i, panes.count - 1)].focus() }
    }

    func focusPane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        panes[index].focus()
    }

    func moveFocus(dx: CGFloat, dy: CGFloat) {
        guard let from = focused ?? panes.first, let to = grid.neighbour(of: from, dx: dx, dy: dy) else { return }
        to.focus()
    }

    func setFontSize(_ size: CGFloat) { panes.forEach { $0.setFontSize(size) } }

    private func updateCount() {
        countLabel.stringValue = panes.count > 1 ? "\(panes.count)/\(GridLayout.maxPanes)" : ""
        layoutTopBar()
    }

    private func responderChanged(_ r: NSResponder?) {
        guard let view = r as? NSView else { return }
        let pane = panes.first { view.isDescendant(of: $0) }
        guard let pane, pane !== focused else { return }
        focused?.isFocused = false
        focused = pane
        pane.isFocused = true
    }

    // MARK: PaneViewDelegate

    func paneWantsClose(_ pane: PaneView) { close(pane) }

    // MARK: Menu actions (first-responder chain)

    @objc func closePane(_ sender: Any?) {
        if let pane = focused ?? panes.last { close(pane) }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        panes.forEach { $0.shutdown() }
        panes.removeAll()
        host?.windowControllerDidClose(self)
    }
}
