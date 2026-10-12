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

/// Top strip: room for the traffic lights and the `+` button.
final class TopBar: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override var isFlipped: Bool { true }

    /// Double-click follows System Settings › Desktop & Dock › "Double-click a window's title bar".
    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil)
        }
    }
}

@MainActor protocol WindowControllerDelegate: AnyObject {
    func makePane(for controller: WindowController, restoring: SessionState.Pane?) -> PaneView
    func windowControllerDidClose(_ controller: WindowController)
    func movePane(_ pane: PaneView, from source: WindowController, toScreenPoint point: NSPoint)
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
        grid.onReorder = { [weak self] order in self?.panes = order }
        grid.onTearOff = { [weak self] pane, point in
            guard let self else { return }
            self.host?.movePane(pane, from: self, toScreenPoint: point)
        }
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
        // Keep pane headers in step with the shell's folder / the running program, like Terminal.
        titleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.panes.forEach { $0.refreshTitle() } }
        }
    }

    private var titleTimer: Timer?

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func layoutAll() {
        guard let content = window?.contentView else { return }
        let b = content.bounds
        topBar.frame = CGRect(x: 0, y: b.height - Theme.topBarHeight, width: b.width, height: Theme.topBarHeight)
        grid.frame = CGRect(x: 0, y: 0, width: b.width, height: b.height - Theme.topBarHeight)
        layoutTopBar()
    }

    private func layoutTopBar() {
        let h = Theme.topBarHeight
        addButton.frame = CGRect(x: 78, y: (h - 22) / 2, width: 24, height: 22)
        countLabel.sizeToFit()
        countLabel.frame.origin = CGPoint(x: addButton.frame.maxX + 6, y: (h - countLabel.frame.height) / 2)
    }

    @objc private func addTapped() {
        (NSApp.delegate as? AppDelegate)?.newPane(nil)
    }

    // MARK: Panes

    /// Adds a terminal; `restoring` reopens one saved from a previous run.
    func addPane(restoring: SessionState.Pane? = nil) {
        guard canAddPane, let host else { return }
        let pane = host.makePane(for: self, restoring: restoring)
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

    /// Takes a pane out without stopping it: it is moving to another window.
    func detach(_ pane: PaneView) {
        guard let i = panes.firstIndex(of: pane) else { return }
        panes.remove(at: i)
        if focused === pane { focused = nil }
        pane.isFocused = false
        grid.setPanes(panes)
        updateCount()
        if panes.isEmpty {
            window?.close()
        } else {
            panes[min(i, panes.count - 1)].focus()
        }
    }

    /// Takes in a running pane from another window.
    func adopt(_ pane: PaneView) {
        guard canAddPane else { return }
        pane.delegate = self
        panes.append(pane)
        grid.setPanes(panes)
        updateCount()
        grid.layoutSubtreeIfNeeded()
        pane.focus()
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

    func paneWantsClose(_ pane: PaneView) { userClose(pane) }

    func paneProcessEnded(_ pane: PaneView) { close(pane) }

    /// Close requested by the user: ask first if Claude (or anything) is still running there.
    func userClose(_ pane: PaneView) {
        let risk = pane.closeRisk
        guard risk != .none else { close(pane); return }
        // Say which one: its number and title, and outline it in red while asking.
        let name = closeName(for: pane)
        pane.markedForClosing = true
        defer { pane.markedForClosing = false }
        if !confirmClose([risk], .pane, name: name) { return }
        close(pane)
    }

    /// How the close question names a pane: its number and title.
    func closeName(for pane: PaneView) -> String {
        let number = (panes.firstIndex(of: pane) ?? 0) + 1
        return "terminal \(number), \u{201C}\(PaneTitle.plain(pane.headerTitle))\u{201D}"
    }

    // MARK: Menu actions (first-responder chain)

    @objc func clearPane(_ sender: Any?) { (focused ?? panes.first)?.clear() }

    @objc func closePane(_ sender: Any?) {
        if let pane = focused ?? panes.last { userClose(pane) }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return confirmClose(panes.map(\.closeRisk), .window)
    }

    func windowWillClose(_ notification: Notification) {
        titleTimer?.invalidate()
        grid.setPanes([])  // ends a pane drag still in progress (and its cursor)
        panes.forEach { $0.shutdown() }
        panes.removeAll()
        host?.windowControllerDidClose(self)
    }
}

/// Asks before quitting or closing cuts something off: a terminal where something is working, or
/// one holding a Claude conversation. True means go ahead. Empty terminals never ask.
enum CloseKind { case pane, window, app }

@MainActor
func confirmClose(_ risks: [PaneView.CloseRisk], _ kind: CloseKind, name: String? = nil) -> Bool {
    let working = risks.filter { $0 == .working }.count
    let talks = risks.filter { $0 == .conversation }.count
    guard working + talks > 0 else { return true }
    func n(_ k: Int, _ one: String, _ many: String) -> String { k == 1 ? "1 \(one)" : "\(k) \(many)" }
    var lines: [String] = []
    let alert = NSAlert()
    switch kind {
    case .app:
        alert.messageText = "Quit Onyx?"
        if working > 0 { lines.append("Something is still working in \(n(working, "terminal", "terminals")); quitting stops it.") }
        lines.append("Your Claude conversations can be reopened next time you open Onyx.")
    case .pane, .window:
        alert.messageText = kind == .window ? "Close this window?" : name.map { "Close \($0)?" } ?? "Close this terminal?"
        if working > 0 {
            lines.append(kind == .pane ? "Something is still working in it (Claude answering, or another program); closing stops it."
                                       : "Something is still working in \(n(working, "terminal", "terminals")); closing stops it.")
        }
        if talks > 0 || working > 0 {
            lines.append(kind == .pane
                ? "Its Claude conversation won't come back when you reopen Onyx; `claude --resume` still finds it."
                : "Its Claude conversations won't come back when you reopen Onyx; `claude --resume` still finds them.")
        }
    }
    alert.informativeText = lines.joined(separator: " ")
    alert.addButton(withTitle: kind == .app ? "Quit" : "Close")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}
