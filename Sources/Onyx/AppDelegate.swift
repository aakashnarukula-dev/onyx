import AppKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate, WindowControllerDelegate {
    let paths = OnyxPaths()
    var settings = Settings()
    private var controllers: [WindowController] = []
    var windowControllers: [WindowController] { controllers }
    private let shell = PaneEnv.loginShell()
    private let launchedAt = ProcessInfo.processInfo.systemUptime
    private let timing = ProcessInfo.processInfo.environment["ONYX_TIMING"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        installLinkClick()
        settings = Settings.load(paths)
        newWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        log("first pane")
        DebugHooks.runScriptIfAny(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if DebugHooks.env["ONYX_SNAPSHOT"] != nil { return .terminateNow }
        let busy = controllers.flatMap(\.panes).filter(\.isBusy).count
        return busy == 0 || confirmClose(busy: busy) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.panes.forEach { $0.shutdown(wait: true) } }
    }

    // MARK: Windows and panes

    private var current: WindowController? {
        controllers.first { $0.window?.isKeyWindow == true } ?? controllers.last
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
        pane.start(shell: shell,
                   args: PaneEnv.shellArgs(shell: shell, command: DebugHooks.paneCommand ?? PaneEnv.claudeCommand),
                   env: PaneEnv.build(base: ProcessInfo.processInfo.environment))
        return pane
    }

    func windowControllerDidClose(_ controller: WindowController) {
        controllers.removeAll { $0 === controller }
    }

    private var developerDir: String { NSHomeDirectory() + "/Developer" }

    /// ⌘-click on a plain URL opens it in the browser, like Terminal.app.
    private func installLinkClick() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard event.modifierFlags.contains(.command), let self,
                  let c = self.controllers.first(where: { $0.window === event.window }) else { return event }
            for pane in c.panes {
                if let url = pane.plainURL(atWindowPoint: event.locationInWindow) {
                    NSWorkspace.shared.open(url)
                    break
                }
            }
            return event
        }
    }

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
