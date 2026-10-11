import AppKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate, WindowControllerDelegate {
    let paths = OnyxPaths()
    lazy var registry = PaneRegistry(paths: paths)
    lazy var accounts = AccountStore(paths: paths, secrets: KeychainStore())
    var settings = Settings()
    /// Env vars for the active accounts, computed once per account change, and the GitHub
    /// login they belong to (the label shown on panes made with them).
    private(set) var accountVars: [String: String] = [:]
    private(set) var accountLogin: String?
    private var refreshGate = RefreshGate()
    private var controllers: [WindowController] = []
    var windowControllers: [WindowController] { controllers }
    private var promptPath = ""
    private let launchedAt = ProcessInfo.processInfo.systemUptime
    private let timing = ProcessInfo.processInfo.environment["ONYX_TIMING"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        settings = Settings.load(paths)
        promptPath = (try? PanePrompt.write(to: paths.home).path) ?? paths.prompt.path
        newWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        log("window")
        refreshAccounts()
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
        c.accessory = AccountsChip(app: self)
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
    /// Non-nil while account env is being (re)computed; panes made meanwhile wait here so they
    /// never start with the previous account's token.
    private var waiting: [(PaneView, String)]? = []

    private func makePane(command defaultCommand: String) -> PaneView {
        let command = pendingCommand ?? defaultCommand
        pendingCommand = nil
        let cwd = FileManager.default.fileExists(atPath: developerDir) ? developerDir : NSHomeDirectory()
        let pane = PaneView(id: UUID().uuidString.lowercased(), cwd: cwd, fontSize: CGFloat(settings.fontSize), registry: registry)
        if waiting != nil {
            waiting?.append((pane, command))
        } else {
            start(pane, command)
        }
        return pane
    }

    private func start(_ pane: PaneView, _ command: String) {
        let env = SessionEnv.build(base: ProcessInfo.processInfo.environment, accountVars: accountVars,
                                   paneId: pane.id, binDir: binDir)
        pane.start(command: command, env: env, accountLabel: accountVars["GH_TOKEN"] != nil ? accountLogin : nil)
    }

    private func startWaitingPanes() {
        let queued = waiting ?? []
        waiting = nil
        queued.forEach { start($0.0, $0.1) }
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

    /// Recomputes account env off the main thread (gh, maybe the GitHub API). New panes wait for
    /// it; only the newest of overlapping refreshes is applied.
    func refreshAccounts() {
        let token = refreshGate.begin()
        if waiting == nil { waiting = [] }
        let settings = self.settings, accounts = self.accounts
        DispatchQueue.global(qos: .userInitiated).async {
            var s = settings
            let defaultLogin = s.activeGitHub == nil ? accounts.githubActiveLogin() : nil
            if let defaultLogin { s.activeGitHub = defaultLogin }
            let vars = SessionEnv.accountVars(settings: s, accounts: accounts)
            DispatchQueue.main.async {
                guard self.refreshGate.accept(token) else { return }
                if let defaultLogin, self.settings.activeGitHub == nil {
                    self.settings.activeGitHub = defaultLogin
                    try? self.settings.save(self.paths)
                }
                self.accountVars = vars
                self.accountLogin = s.activeGitHub
                self.cacheIdentity()
                self.startWaitingPanes()
                self.log("accounts ready")
                NotificationCenter.default.post(name: .onyxAccountsChanged, object: nil)
            }
        }
        // If gh hangs (offline, keychain prompt), don't leave terminals blank: start them without
        // account env after a few seconds; the refresh still lands for later panes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard self.refreshGate.isRefreshing, self.waiting?.isEmpty == false else { return }
            self.startWaitingPanes()
        }
        NotificationCenter.default.post(name: .onyxAccountsChanged, object: nil)
    }

    func setActiveGitHub(_ login: String) {
        settings.activeGitHub = login
        saveAndRefresh()
    }

    func setActiveVercel(_ label: String) {
        settings.activeVercel = label
        saveAndRefresh()
    }

    func setIdentity(_ id: GitHubIdentity) {
        settings.identities[id.login] = id
        saveAndRefresh()
    }

    func removeVercel(_ label: String) {
        accounts.secrets.delete(label)
        settings.vercelLabels.removeAll { $0 == label }
        if settings.activeVercel == label { settings.activeVercel = settings.vercelLabels.first }
        saveAndRefresh()
    }

    /// Validates the token with `vercel whoami`, then stores it in the Keychain and makes it active.
    func addVercel(label: String, token: String, done: @escaping @MainActor (Bool) -> Void) {
        let accounts = self.accounts
        DispatchQueue.global(qos: .userInitiated).async {
            let user = accounts.validateVercel(token: token)
            DispatchQueue.main.async {
                guard user != nil, (try? accounts.secrets.set(label, token)) != nil else { done(false); return }
                if !self.settings.vercelLabels.contains(label) { self.settings.vercelLabels.append(label) }
                self.settings.activeVercel = label
                self.saveAndRefresh()
                done(true)
            }
        }
    }

    private func saveAndRefresh() {
        try? settings.save(paths)
        refreshAccounts()
    }

    /// Remembers the API-reported commit identity so later launches skip the network call.
    private func cacheIdentity() {
        guard let login = accountLogin, settings.identities[login] == nil,
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

    private var settingsWindow: SettingsWindow?

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindow(app: self) }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    var fontSize: Double { settings.fontSize }

    func applyFontSize(_ size: Double) { setFont(size) }

    private func log(_ what: String) {
        guard timing else { return }
        FileHandle.standardError.write(Data(String(format: "[onyx] %@ (+%.0f ms since launch)\n", what,
                                                   (ProcessInfo.processInfo.systemUptime - launchedAt) * 1000).utf8))
    }
}

extension Notification.Name {
    static let onyxAccountsChanged = Notification.Name("onyxAccountsChanged")
}
