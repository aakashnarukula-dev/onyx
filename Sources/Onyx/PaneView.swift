import AppKit
import OnyxCore
import SwiftTerm

@MainActor protocol PaneViewDelegate: AnyObject {
    func paneWantsClose(_ pane: PaneView)
    func paneProcessEnded(_ pane: PaneView)
}

/// One independent terminal: a thin header (title, close) over a SwiftTerm view.
final class PaneView: NSView, @preconcurrency LocalProcessTerminalViewDelegate {
    let terminal: LocalProcessTerminalView
    weak var delegate: PaneViewDelegate?
    /// Dragging the header moves the pane to another place in the grid.
    var onHeaderDrag: ((PaneView, PaneHeader.DragPhase, NSEvent) -> Void)?
    let header = PaneHeader()
    private var closed = false

    var isFocused = false { didSet { updateFocusLook() } }

    private let cwd: String
    private var programTitle: String?

    /// Builds the view; the shell starts on `start(shell:args:env:)`.
    init(cwd: String, fontSize: CGFloat) {
        self.cwd = cwd
        terminal = LocalProcessTerminalView(frame: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = Theme.cornerRadius
        layer?.cornerCurve = .continuous

        terminal.font = Theme.font(size: fontSize)
        terminal.nativeBackgroundColor = Theme.background
        terminal.nativeForegroundColor = Theme.foreground
        terminal.caretColor = Theme.cursor
        terminal.installColors(Theme.ansi)
        terminal.optionAsMetaKey = true
        terminal.processDelegate = self
        // Terminal.app keeps 10,000 lines by default; SwiftTerm's default is 500.
        terminal.changeScrollback(10_000)
        // No scroll bar (trackpad / wheel still scroll); SwiftTerm gives its width back to the text.
        terminal.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }

        header.title = (cwd as NSString).abbreviatingWithTildeInPath
        header.onClose = { [weak self] in self?.requestClose() }
        header.onClick = { [weak self] in self?.focus() }
        header.onDrag = { [weak self] phase, event in
            guard let self else { return }
            self.onHeaderDrag?(self, phase, event)
        }
        addSubview(header)
        addSubview(terminal)
        updateFocusLook()
    }

    func start(shell: String, args: [String], execName: String, env: [String: String]) {
        guard !closed, !terminal.process.running else { return }
        terminal.startProcess(executable: shell, args: args,
                              environment: env.map { "\($0.key)=\($0.value)" },
                              execName: execName, currentDirectory: cwd)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Theme.headerHeight)
        // Inset so the text clears the rounded corners.
        terminal.frame = CGRect(x: Theme.padding, y: Theme.headerHeight, width: max(0, bounds.width - Theme.padding * 2),
                                height: max(0, bounds.height - Theme.headerHeight - Theme.padding))
    }

    /// One Character per cell; emoji and other non-BMP characters resolved through the terminal.
    private func lineText(_ line: BufferLine, trimRight: Bool = false) -> String {
        let t = terminal.getTerminal()
        return line.translateToString(trimRight: trimRight, characterProvider: { t.getCharacter(for: $0) })
    }

    var headerTitle: String { header.title }

    /// Text of the top visible row (tests: did scrolling move the view?).
    func topLine() -> String {
        let t = terminal.getTerminal()
        guard let line = t.getLine(row: 0) else { return "" }
        return lineText(line, trimRight: true)
    }

    func getTerminalSize() -> (cols: Int, rows: Int, lines: Int) {
        let t = terminal.getTerminal()
        return (t.cols, t.rows, t.buffer.yDisp + t.rows)
    }

    /// Non-empty visible lines (tests and snapshots).
    func visibleText() -> [String] {
        let t = terminal.getTerminal()
        return (0..<t.rows).compactMap { t.getLine(row: $0).map { lineText($0, trimRight: true) } }.filter { !$0.isEmpty }
    }

    func focus() { window?.makeFirstResponder(terminal) }

    /// ⌘K: clear screen and scrollback. Ctrl-L (redraw) goes only to the shell or Claude; any
    /// other program (a password prompt, `cat`, an editor) would take it as input.
    func clear() {
        terminal.feed(text: TerminalClear.localSequence)
        let fg = foregroundPid
        if fg == terminal.process.shellPid || (fg.flatMap(executablePath)?.contains("claude") ?? false) {
            terminal.send(TerminalClear.redrawKey)
        }
    }

    /// Leader of the terminal's foreground process group (the program the user is talking to).
    var foregroundPid: pid_t? {
        let fd = terminal.process.childfd
        guard fd >= 0 else { return nil }
        let pgid = tcgetpgrp(fd)
        return pgid > 0 ? pgid : nil
    }

    /// Header text like Terminal.app's: the folder while the shell is in front, otherwise the
    /// running program's own title (or its name).
    func refreshTitle() {
        guard !closed, terminal.process.running else { return }
        let shell = terminal.process.shellPid
        let fg = foregroundPid
        let text: String
        if fg == nil || fg == shell {
            text = currentDirectory(of: shell).map { ($0 as NSString).abbreviatingWithTildeInPath } ?? header.title
            programTitle = nil
        } else if let t = programTitle, !t.isEmpty {
            text = t
        } else {
            text = fg.flatMap(processName) ?? header.title
        }
        if header.title != text { header.title = text }
    }

    func setFontSize(_ size: CGFloat) { terminal.font = Theme.font(size: size) }

    func requestClose() { delegate?.paneWantsClose(self) }

    /// What to reopen this terminal as: the Claude conversation running in it (in Claude's
    /// folder), else the shell's folder.
    func sessionPane(_ claude: ClaudeSessions) -> SessionState.Pane {
        let shell = terminal.process.shellPid
        guard !closed, terminal.process.running, shell > 0 else { return resuming ?? .init(cwd: cwd, claudeSession: nil) }
        for pid in childPids(of: shell) {
            if let s = claude.running(pid: pid) {
                resuming = nil
                return .init(cwd: s.cwd, claudeSession: s.id)
            }
        }
        // A reopened conversation counts as here until its Claude has been seen running: it may
        // still be starting, or `--resume` may have failed (login expired, Ctrl-C) — either way
        // quitting now must not lose it.
        return resuming ?? .init(cwd: currentDirectory(of: shell) ?? cwd, claudeSession: nil)
    }

    /// The saved conversation this pane was reopened to resume, until Claude is seen running.
    var resuming: SessionState.Pane?

    /// True while something other than the bare shell runs in the pane (Claude, a build, …).
    var isBusy: Bool {
        guard !closed, terminal.process.running else { return false }
        return !childPids(of: terminal.process.shellPid).isEmpty
    }

    /// Starts ending the shell and everything under it and returns what must be reaped.
    /// Interactive zsh ignores SIGTERM, so the shell gets SIGHUP; its children get both.
    func beginShutdown() -> PaneProcesses? {
        guard !closed else { return nil }
        closed = true
        let shell = terminal.process.shellPid
        guard terminal.process.running, shell > 0 else { return nil }
        let children = childPids(of: shell)
        children.forEach { kill($0, SIGHUP); kill($0, SIGTERM) }
        kill(shell, SIGHUP)
        terminal.process.terminate()
        return PaneProcesses(shell: shell, children: children)
    }

    /// Ends the pane's processes; the reaping (SIGKILL after 2 s) happens in the background.
    func shutdown() {
        guard let p = beginShutdown() else { return }
        DispatchQueue.global(qos: .utility).async { PaneProcesses.reap([p], within: 2) }
    }

    private func updateFocusLook() {
        layer?.borderColor = (isFocused ? Theme.accent : Theme.borderIdle).cgColor
        layer?.borderWidth = isFocused ? 1.5 : 1
        header.focused = isFocused
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        programTitle = title
        refreshTitle()
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

func executablePath(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
}

func processName(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 256)
    return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
}

func currentDirectory(of pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
        String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
    }
}

/// A closed pane's shell and its children, to be reaped.
struct PaneProcesses: Sendable {
    let shell: pid_t
    let children: [pid_t]

    /// Waits until every shell is reaped and every child gone, SIGKILLing what is left at the
    /// deadline. One shared deadline, so quitting with many panes takes at most `seconds`.
    static func reap(_ all: [PaneProcesses], within seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        var pending = all.map(\.shell)
        let children = all.flatMap(\.children)
        while true {
            var status: Int32 = 0
            pending.removeAll { waitpid($0, &status, WNOHANG) != 0 }
            if pending.isEmpty && children.allSatisfy({ kill($0, 0) != 0 }) { return }
            if Date() > deadline {
                children.forEach { kill($0, SIGKILL) }
                pending.forEach { kill($0, SIGKILL); waitpid($0, &status, 0) }
                return
            }
            usleep(20_000)
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
    private let closeButton = HoverButton(title: "×")
    private let dot = NSView()
    var onClose: (() -> Void)?
    var onClick: (() -> Void)?

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var focused = false {
        didSet {
            titleLabel.textColor = focused ? Theme.headerTextFocused : Theme.headerText
            dot.layer?.backgroundColor = (focused ? Theme.accent : Theme.dotIdle).cgColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.cell?.usesSingleLineMode = true
        addSubview(titleLabel)
        titleLabel.font = Theme.ui(11.5, .semibold)
        titleLabel.textColor = Theme.headerText
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = Theme.dotIdle.cgColor
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
        titleLabel.frame = CGRect(x: 22, y: (h - 15) / 2, width: max(0, closeButton.frame.minX - 30), height: 15)
    }

    enum DragPhase { case began, moved, ended }
    var onDrag: ((DragPhase, NSEvent) -> Void)?
    private var downAt: CGPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        onClick?()
        downAt = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt else { return }
        let p = event.locationInWindow
        if !dragging, hypot(p.x - downAt.x, p.y - downAt.y) > 4 {
            dragging = true
            onDrag?(.began, event)
        }
        if dragging { onDrag?(.moved, event) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { onDrag?(.ended, event) }
        downAt = nil
        dragging = false
    }

    override func resetCursorRects() {
        addCursorRect(CGRect(x: 0, y: 0, width: max(0, closeButton.frame.minX - 4), height: bounds.height), cursor: .openHand)
    }

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
