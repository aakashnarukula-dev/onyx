import AppKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate, WindowControllerDelegate {
    let paths = OnyxPaths()
    lazy var registry = PaneRegistry(paths: paths)
    lazy var accounts = AccountStore(paths: paths, secrets: KeychainStore())
    var settings = Settings()
    /// Env vars for the active accounts, computed once per account change.
    private(set) var accountVars: [String: String] = [:]
    private var controllers: [WindowController] = []
    var windowControllers: [WindowController] { controllers }
    private var promptPath = ""
    private let launchedAt = ProcessInfo.processInfo.systemUptime
    private let timing = ProcessInfo.processInfo.environment["ONYX_TIMING"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        settings = Settings.load(paths)
        promptPath = (try? PanePrompt.write(to: paths.home).path) ?? paths.prompt.path
        accountVars = SessionEnv.accountVars(settings: settings, accounts: accounts)
        cacheIdentity()
        newWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        log("first pane")
        DebugHooks.runScriptIfAny(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.panes.forEach { $0.shutdown() } }
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
        makePane(command: DebugHooks.paneCommand ?? claudeCommand)
    }

    /// Opens a pane running `command` (e.g. `gh auth login`) instead of Claude.
    func openPane(running command: String) {
        pendingCommand = command
        newPane(nil)
    }

    private var pendingCommand: String?

    private func makePane(command defaultCommand: String) -> PaneView {
        let command = pendingCommand ?? defaultCommand
        pendingCommand = nil
        let paneId = UUID().uuidString.lowercased()
        let env = SessionEnv.build(base: ProcessInfo.processInfo.environment, accountVars: accountVars,
                                   paneId: paneId, binDir: binDir)
        let cwd = FileManager.default.fileExists(atPath: developerDir) ? developerDir : NSHomeDirectory()
        return PaneView(id: paneId, command: command, env: env, cwd: cwd, fontSize: CGFloat(settings.fontSize),
                        accountLabel: accountVars["GH_TOKEN"] != nil ? settings.activeGitHub : nil, registry: registry)
    }

    func windowControllerDidClose(_ controller: WindowController) {
        controllers.removeAll { $0 === controller }
    }

    private var developerDir: String { NSHomeDirectory() + "/Developer" }

    /// Both executables sit side by side (in the .app's MacOS dir, or in .build/<config>).
    private var binDir: String { Bundle.main.executableURL?.deletingLastPathComponent().path ?? "" }

    private var claudeCommand: String {
        let prompt = "'" + promptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "if command -v claude >/dev/null 2>&1; then claude --permission-mode auto --append-system-prompt-file \(prompt); "
            + "else printf '\\033[2mclaude not found — plain shell\\033[0m\\n'; fi"
    }

    // MARK: Accounts

    /// Re-reads settings-driven account env (call after the active account changes).
    func refreshAccounts() {
        accountVars = SessionEnv.accountVars(settings: settings, accounts: accounts)
        cacheIdentity()
        NotificationCenter.default.post(name: .onyxAccountsChanged, object: nil)
    }

    /// Remembers the API-reported commit identity so later launches skip the network call.
    private func cacheIdentity() {
        guard let login = settings.activeGitHub, settings.identities[login] == nil,
              let name = accountVars["GIT_AUTHOR_NAME"], let email = accountVars["GIT_AUTHOR_EMAIL"] else { return }
        settings.identities[login] = GitHubIdentity(login: login, name: name, email: email)
        try? settings.save(paths)
    }

    // MARK: Menu actions

    @objc func closePane(_ sender: Any?) { current?.closePane(sender) }

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

    @objc func showSettings(_ sender: Any?) {}

    private func log(_ what: String) {
        guard timing else { return }
        FileHandle.standardError.write(Data(String(format: "[onyx] %@ (+%.0f ms since launch)\n", what,
                                                   (ProcessInfo.processInfo.systemUptime - launchedAt) * 1000).utf8))
    }
}

extension Notification.Name {
    static let onyxAccountsChanged = Notification.Name("onyxAccountsChanged")
}
