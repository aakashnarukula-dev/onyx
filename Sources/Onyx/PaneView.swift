import AppKit
import OnyxCore
import SwiftTerm

@MainActor protocol PaneViewDelegate: AnyObject {
    func paneWantsClose(_ pane: PaneView)
    func paneProcessEnded(_ pane: PaneView)
}

/// One independent terminal: a thin header (title, account, close) over a SwiftTerm view.
final class PaneView: NSView, @preconcurrency LocalProcessTerminalViewDelegate {
    let id: String
    let terminal: LocalProcessTerminalView
    weak var delegate: PaneViewDelegate?
    private let header = PaneHeader()
    private let registry: PaneRegistry
    private var closed = false

    var isFocused = false { didSet { updateFocusLook() } }

    private let cwd: String

    /// Builds the view; the shell starts on `start(command:env:)`.
    init(id: String, cwd: String, fontSize: CGFloat, registry: PaneRegistry) {
        self.cwd = cwd
        self.id = id
        self.registry = registry
        terminal = LocalProcessTerminalView(frame: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        layer?.borderWidth = 1

        terminal.font = Theme.font(size: fontSize)
        terminal.nativeBackgroundColor = Theme.background
        terminal.nativeForegroundColor = Theme.foreground
        terminal.caretColor = Theme.cursor
        terminal.installColors(Theme.ansi)
        terminal.optionAsMetaKey = true
        terminal.processDelegate = self
        // SwiftTerm always shows a legacy scroller; the trackpad still scrolls without it.
        terminal.subviews.filter { $0 is NSScroller }.forEach { $0.isHidden = true }

        header.title = (cwd as NSString).abbreviatingWithTildeInPath
        header.onClose = { [weak self] in self?.requestClose() }
        header.onClick = { [weak self] in self?.focus() }
        addSubview(header)
        addSubview(terminal)
        updateFocusLook()
    }

    /// Runs `command` inside an interactive login zsh; the pane falls back to a plain shell after it.
    func start(command: String, env: [String: String], accountLabel: String?) {
        guard !closed, !terminal.process.running else { return }
        header.account = accountLabel
        let shellCmd = "\(command); exec /bin/zsh -l -i"
        terminal.startProcess(executable: "/bin/zsh", args: ["-l", "-i", "-c", shellCmd],
                              environment: env.map { "\($0.key)=\($0.value)" },
                              execName: "-zsh", currentDirectory: cwd)
        try? registry.markAlive(paneId: id, pid: terminal.process.shellPid)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Theme.headerHeight)
        terminal.frame = CGRect(x: 1, y: Theme.headerHeight, width: max(0, bounds.width - 2),
                                height: max(0, bounds.height - Theme.headerHeight - 1))
    }

    /// Non-empty visible lines (tests and snapshots).
    func visibleText() -> [String] {
        let t = terminal.getTerminal()
        return (0..<t.rows).compactMap { t.getLine(row: $0)?.translateToString(trimRight: true) }.filter { !$0.isEmpty }
    }

    func focus() { window?.makeFirstResponder(terminal) }

    func setFontSize(_ size: CGFloat) { terminal.font = Theme.font(size: size) }

    func requestClose() { delegate?.paneWantsClose(self) }

    /// True while something other than the bare shell runs in the pane (Claude, a build, …).
    var isBusy: Bool {
        guard !closed, terminal.process.running else { return false }
        return !childPids(of: terminal.process.shellPid).isEmpty
    }

    /// Ends the shell and everything under it. Interactive zsh ignores SIGTERM, so hang up the
    /// children and the shell, reap the shell (SwiftTerm stops watching it on terminate), and
    /// SIGKILL whatever is left after a grace period. `wait` blocks (used on quit, when a
    /// background reaper would die with the app).
    func shutdown(wait: Bool = false) {
        guard !closed else { return }
        closed = true
        registry.markClosed(paneId: id)
        let shell = terminal.process.shellPid
        guard terminal.process.running, shell > 0 else { return }
        let children = childPids(of: shell)
        children.forEach { kill($0, SIGHUP); kill($0, SIGTERM) }
        kill(shell, SIGHUP)
        terminal.process.terminate()
        let reap = { @Sendable in
            let deadline = Date().addingTimeInterval(wait ? 1.5 : 2)
            var status: Int32 = 0
            func gone(_ p: pid_t) -> Bool { kill(p, 0) != 0 }
            while !(waitpid(shell, &status, WNOHANG) != 0 && children.allSatisfy(gone)) {
                if Date() > deadline {
                    children.forEach { kill($0, SIGKILL) }
                    kill(shell, SIGKILL)
                    waitpid(shell, &status, 0)
                    return
                }
                usleep(20_000)
            }
        }
        if wait { reap() } else { DispatchQueue.global(qos: .utility).async(execute: reap) }
    }

    private func updateFocusLook() {
        layer?.borderColor = (isFocused ? Theme.borderFocused : Theme.borderIdle).cgColor
        header.focused = isFocused
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        if !title.isEmpty { header.title = title }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL else { return }
        header.title = (url.path as NSString).abbreviatingWithTildeInPath
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.delegate?.paneProcessEnded(self)
        }
    }
}

/// Direct children of `pid`.
func childPids(of pid: pid_t) -> [pid_t] {
    guard pid > 0 else { return [] }
    var buf = [pid_t](repeating: 0, count: 64)
    let n = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
    return n > 0 ? Array(buf.prefix(Int(n))).filter { $0 > 0 } : []
}

/// The 24 pt strip above each terminal.
final class PaneHeader: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let accountLabel = NSTextField(labelWithString: "")
    private let closeButton = HoverButton(title: "×")
    private let dot = NSView()
    var onClose: (() -> Void)?
    var onClick: (() -> Void)?

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var account: String? {
        didSet { accountLabel.stringValue = account.map { "gh: \($0)" } ?? "" }
    }

    var focused = false {
        didSet {
            titleLabel.textColor = focused ? Theme.headerTextFocused : Theme.headerText
            dot.layer?.backgroundColor = (focused ? Theme.accent : Theme.borderFocused).cgColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        for l in [titleLabel, accountLabel] {
            l.lineBreakMode = .byTruncatingMiddle
            l.cell?.usesSingleLineMode = true
            addSubview(l)
        }
        titleLabel.font = Theme.ui(11.5, .semibold)
        titleLabel.textColor = Theme.headerText
        accountLabel.font = Theme.ui(10.5)
        accountLabel.textColor = Theme.muted
        accountLabel.alignment = .right
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = Theme.borderFocused.cgColor
        addSubview(dot)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.toolTip = "Close terminal (⌘W)"
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = bounds.height
        dot.frame = CGRect(x: 10, y: (h - 6) / 2, width: 6, height: 6)
        closeButton.frame = CGRect(x: bounds.width - 24, y: (h - 18) / 2, width: 18, height: 18)
        let accW = min(160, accountLabel.intrinsicContentSize.width)
        accountLabel.frame = CGRect(x: closeButton.frame.minX - 8 - accW, y: (h - 14) / 2, width: accW, height: 14)
        titleLabel.frame = CGRect(x: 22, y: (h - 15) / 2, width: max(0, accountLabel.frame.minX - 30), height: 15)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    @objc private func closeTapped() { onClose?() }
}

/// Borderless text button that brightens on hover.
final class HoverButton: NSButton {
    var normalColor = Theme.muted { didSet { refresh() } }
    var hoverColor = Theme.headerTextFocused
    var fontSize: CGFloat = 15 { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }

    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
        focusRingType = .none
        refresh()
    }

    override var title: String { didSet { refresh() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func refresh() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: hovering ? hoverColor : normalColor,
            .font: Theme.ui(fontSize, .medium),
            .paragraphStyle: style,
        ])
        layer?.backgroundColor = hovering ? Theme.hex(0x1c1c1c).cgColor : NSColor.clear.cgColor
    }
}
