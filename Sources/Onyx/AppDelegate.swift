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
        zshDir = (try? ZshIntegration.write(to: paths.home.appendingPathComponent("zsh")).path) ?? ""
        newWindow(nil)
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
        if DebugHooks.env["ONYX_SNAPSHOT"] != nil { return .terminateNow }
        let busy = controllers.flatMap(\.panes).filter(\.isBusy).count
        return busy == 0 || confirmClose(busy: busy) ? .terminateNow : .terminateCancel
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
    @objc func newPane(_ sender: Any?) {
        let t0 = ProcessInfo.processInfo.systemUptime
        if let c = current, c.canAddPane {
            c.addPane()
        } else {
            newWindow(sender)
        }
        log(String(format: "new pane %.1f ms", (ProcessInfo.processInfo.systemUptime - t0) * 1000))
    }

    @objc func newWindow(_ sender: Any?) {
        let frame: NSRect
        if let last = current?.window?.frame {
            frame = last.offsetBy(dx: 28, dy: -28)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = CGSize(width: min(1280, screen.width * 0.85), height: min(820, screen.height * 0.85))
            frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        }
        let c = WindowController(owner: self, frame: frame)
        controllers.append(c)
        c.showWindow(nil)
        c.addPane()
    }

    func makePane(for controller: WindowController) -> PaneView {
        let cwd = FileManager.default.fileExists(atPath: developerDir) ? developerDir : NSHomeDirectory()
        let pane = PaneView(cwd: cwd, fontSize: CGFloat(settings.fontSize))
        let base = ProcessInfo.processInfo.environment
        let launch = PaneEnv.launch(shell: shell, firstCommand: DebugHooks.paneCommand ?? PaneEnv.claudeCommand,
                                    zdotdir: zshDir, userZdotdir: base["ZDOTDIR"])
        pane.start(shell: shell, args: launch.args, execName: launch.execName,
                   env: PaneEnv.build(base: base).merging(launch.env) { _, new in new })
        return pane
    }

    func windowControllerDidClose(_ controller: WindowController) {
        controllers.removeAll { $0 === controller }
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
        try? settings.save(paths)
        controllers.forEach { $0.setFontSize(CGFloat(settings.fontSize)) }
    }

    func log(_ what: String) {
        guard timing else { return }
        FileHandle.standardError.write(Data(String(format: "[onyx] %@ (+%.0f ms since launch)\n", what,
                                                   (ProcessInfo.processInfo.systemUptime - launchedAt) * 1000).utf8))
    }
}
