import AppKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate, WindowControllerDelegate {
    let paths = OnyxPaths()
    var settings = Settings()
    private var controllers: [WindowController] = []
    var windowControllers: [WindowController] { controllers }
    private let shell = PaneEnv.loginShell()
    private var zshDir = ""
    private let launchedAt = ProcessInfo.processInfo.systemUptime
    private let timing = ProcessInfo.processInfo.environment["ONYX_TIMING"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        settings = Settings.load(paths)
        updateAssistantMenu()
        zshDir = (try? ZshIntegration.write(to: paths.home.appendingPathComponent("zsh")).path) ?? ""
        if let saved = usesRealHome ? SessionState.load(paths) : nil, askToReopen(saved) {
            saved.windows.forEach(reopen)
        } else {
            newWindow(nil)
        }
        if usesRealHome {
            // Kept current all the time, so a force quit or crash still leaves it behind.
            sessionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveSession() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        log("first pane")
        DebugHooks.runScriptIfAny(self)
    }

    /// Like Terminal.app: closing the last window leaves Onyx running; the Dock icon reopens one.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        DebugHooks.env["ONYX_SNAPSHOT"] != nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controllers.isEmpty { newWindow(nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard DebugHooks.env["ONYX_SNAPSHOT"] != nil || confirmClose(controllers.flatMap(\.panes).map(\.closeRisk), .app) else {
            return .terminateCancel
        }
        // Record what is open before the panes stop, then stop recording.
        saveSession()
        terminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Signal every pane first, then reap them all against one deadline.
        log("quit: stopping panes")
        let all = controllers.flatMap(\.panes).compactMap { $0.beginShutdown() }
        PaneProcesses.reap(all, within: 3)
        log("quit: \(all.count) panes stopped")
    }

    // MARK: Windows and panes

    private var current: WindowController? {
        controllers.first { $0.window?.isMainWindow == true } ?? controllers.last
    }

    /// ⌘N: a new terminal in the current window, or a new window once it holds six.
    @objc func newClaudePane(_ sender: Any?) { addPane(assistant: .claude) }
    @objc func newCodexPane(_ sender: Any?) { addPane(assistant: .codex) }

    @objc func chooseAssistant(_ sender: NSMenuItem) {
        guard Assistant.allCases.indices.contains(sender.tag) else { return }
        settings.assistant = Assistant.allCases[sender.tag]
        if usesRealHome { try? settings.save(paths) }
        updateAssistantMenu()
    }

    private func updateAssistantMenu() {
        guard let menu = NSApp.mainMenu?.item(withTitle: "Shell")?.submenu?
            .item(withTitle: "Default Assistant")?.submenu else { return }
        for item in menu.items {
            item.state = Assistant.allCases[item.tag] == settings.assistant ? .on : .off
        }
    }

    @objc func newPane(_ sender: Any?) { addPane(assistant: settings.assistant) }

    private func addPane(assistant: Assistant) {
        let t0 = ProcessInfo.processInfo.systemUptime
        if let c = current, c.canAddPane {
            c.addPane(assistant: assistant)
        } else {
            openWindow(assistant: assistant)
        }
        log(String(format: "new pane %.1f ms", (ProcessInfo.processInfo.systemUptime - t0) * 1000))
    }

    @objc func newWindow(_ sender: Any?) { openWindow(assistant: settings.assistant) }

    private func openWindow(assistant: Assistant) {
        let frame: NSRect
        if let last = current?.window?.frame {
            frame = last.offsetBy(dx: 28, dy: -28)
        } else {
            frame = defaultFrame
        }
        let c = WindowController(owner: self, frame: frame)
        controllers.append(c)
        c.showWindow(nil)
        c.addPane(assistant: assistant)
    }

    private var defaultFrame: NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: min(1280, screen.width * 0.85), height: min(820, screen.height * 0.85))
        return NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Reopening what was open

    private var claude: ClaudeSessions { PaneView.claude }
    private var sessionTimer: Timer?
    private var terminating = false
    /// Test runs (`ONYX_SNAPSHOT`) leave the real session and settings alone unless given their own ONYX_HOME.
    private var usesRealHome: Bool {
        DebugHooks.env["ONYX_SNAPSHOT"] == nil || DebugHooks.env["ONYX_HOME"] != nil
    }

    /// Asks whether to bring back last time's terminals, when they held Claude conversations
    /// (empty terminals aren't worth asking about). Test runs reopen without asking.
    private func askToReopen(_ saved: SessionState) -> Bool {
        let n = saved.conversations(where: claude.hasTranscript).count
            + saved.windows.flatMap(\.panes).filter { $0.assistant == .codex }.count
        guard n > 0 else { return false }
        if DebugHooks.env["ONYX_SNAPSHOT"] != nil { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reopen your last terminals?"
        alert.informativeText = "\(n) saved assistant terminals from last time. Claude resumes its conversation; Codex opens its conversation picker in the saved folder."
            + " Start Fresh opens one new terminal. You can still use claude --resume or codex resume later."
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Start Fresh")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Opens a saved window: same place (if still on a screen), same terminals in the same order.
    private func reopen(_ saved: SessionState.Window) {
        var frame = defaultFrame
        if saved.frame.count == 4 {
            let f = NSRect(x: saved.frame[0], y: saved.frame[1], width: saved.frame[2], height: saved.frame[3])
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f) }) { frame = f }
        }
        let c = WindowController(owner: self, frame: frame)
        controllers.append(c)
        c.showWindow(nil)
        let panes = saved.panes.isEmpty ? [nil] : saved.panes.prefix(GridLayout.maxPanes).map { Optional($0) }
        panes.forEach { c.addPane(restoring: $0) }
    }

    func saveSession() {
        guard usesRealHome, !terminating else { return }
        let windows = controllers.compactMap { c -> SessionState.Window? in
            guard let f = c.window?.frame, !c.panes.isEmpty else { return nil }
            return .init(frame: [f.minX, f.minY, f.width, f.height], panes: c.panes.map { $0.sessionPane(claude) })
        }
        try? SessionState(windows: windows).save(paths)
    }

    func makePane(for controller: WindowController, restoring: SessionState.Pane?, assistant: Assistant?) -> PaneView {
        var cwd = FileManager.default.fileExists(atPath: developerDir) ? developerDir : NSHomeDirectory()
        let selected = restoring.map { $0.assistant ?? .claude } ?? assistant ?? settings.assistant
        var command = selected.command
        var resuming: SessionState.Pane?
        if let restoring {
            var isDir: ObjCBool = false
            let folderThere = FileManager.default.fileExists(atPath: restoring.cwd, isDirectory: &isDir) && isDir.boolValue
            if folderThere { cwd = restoring.cwd }
            if selected == .codex { command = "codex resume" }
            // Back into the same conversation. Claude finds it by folder, so only in its own folder;
            // one that never got a message starts fresh.
            if folderThere, let id = restoring.claudeSession, claude.hasTranscript(id: id) {
                command = ClaudeSessions.resumeCommand(id: id)
                resuming = restoring
            }
        }
        let pane = PaneView(cwd: cwd, fontSize: CGFloat(settings.fontSize))
        pane.assistant = selected
        pane.resuming = resuming
        let base = ProcessInfo.processInfo.environment
        let launch = PaneEnv.launch(shell: shell, firstCommand: DebugHooks.paneCommand ?? command,
                                    zdotdir: zshDir, userZdotdir: base["ZDOTDIR"])
        pane.start(shell: shell, args: launch.args, execName: launch.execName,
                   env: PaneEnv.build(base: base).merging(launch.env) { _, new in new })
        return pane
    }

    func windowControllerDidClose(_ controller: WindowController) {
        controllers.removeAll { $0 === controller }
        saveSession()  // a window closed on purpose doesn't come back
    }

    /// A pane dragged out of `source` and let go at `point` (screen): into the Onyx window under
    /// the point if it has room, else into a new window placed where it was let go.
    func movePane(_ pane: PaneView, from source: WindowController, toScreenPoint point: NSPoint) {
        let target = controllers.first { $0 !== source && $0.canAddPane && ($0.window?.frame.contains(point) ?? false) }
        let size = CGSize(width: max(pane.frame.width + Theme.margin * 2, 640),
                          height: max(pane.frame.height + Theme.topBarHeight + Theme.margin * 2, 400))
        source.detach(pane)
        if let target {
            target.adopt(pane)
            target.window?.makeKeyAndOrderFront(nil)
            return
        }
        // The new window's top bar sits under the cursor, kept on the screen it was let go on.
        var frame = NSRect(x: point.x - size.width / 2, y: point.y - size.height + Theme.topBarHeight / 2,
                           width: size.width, height: size.height)
        if let screen = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        let c = WindowController(owner: self, frame: frame)
        controllers.append(c)
        c.showWindow(nil)
        c.adopt(pane)
    }

    private var developerDir: String { NSHomeDirectory() + "/Developer" }

    // MARK: Menu actions

    @objc func closePane(_ sender: Any?) { current?.closePane(sender) }

    @objc func clearPane(_ sender: Any?) { current?.clearPane(sender) }

    @objc func focusPane(_ sender: NSMenuItem) { current?.focusPane(at: sender.tag) }

    @objc func moveFocus(_ sender: NSMenuItem) {
        let dirs: [(CGFloat, CGFloat)] = [(-1, 0), (1, 0), (0, 1), (0, -1)]
        let d = dirs[sender.tag]
        current?.moveFocus(dx: d.0, dy: d.1)
    }

    @objc func biggerFont(_ sender: Any?) { setFont(settings.fontSize + 1) }
    @objc func smallerFont(_ sender: Any?) { setFont(settings.fontSize - 1) }
    @objc func defaultFont(_ sender: Any?) { setFont(Settings().fontSize) }

    private func setFont(_ size: Double) {
        settings.fontSize = min(max(size, 9), 28)
        if usesRealHome { try? settings.save(paths) }  // test runs don't touch the real settings
        controllers.forEach { $0.setFontSize(CGFloat(settings.fontSize)) }
    }

    func log(_ what: String) {
        guard timing else { return }
        FileHandle.standardError.write(Data(String(format: "[onyx] %@ (+%.0f ms since launch)\n", what,
                                                   (ProcessInfo.processInfo.systemUptime - launchedAt) * 1000).utf8))
    }
}
