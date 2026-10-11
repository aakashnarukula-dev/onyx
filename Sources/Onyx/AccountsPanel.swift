import AppKit
import OnyxCore

/// GitHub + Vercel account list with an active pick, add/remove and identity editing.
/// Used in the top-bar popover and in Settings.
final class AccountsPanel: NSView {
    private let app: AppDelegate
    private let stack = NSStackView()
    private var logins: [String] = []
    private var form: NSView?
    private let width: CGFloat = 320

    init(app: AppDelegate) {
        self.app = app
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .onyxAccountsChanged, object: nil)
        reloadLogins()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Asks `gh` for its logins off the main thread, then redraws.
    func reloadLogins() {
        let accounts = app.accounts
        rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = accounts.githubLogins()
            DispatchQueue.main.async { [weak self] in
                self?.logins = found
                self?.rebuild()
            }
        }
    }

    @objc private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let s = app.settings

        stack.addArrangedSubview(sectionTitle("GITHUB"))
        if logins.isEmpty { stack.addArrangedSubview(note("No gh logins found.")) }
        for login in logins {
            let row = radioRow(login, selected: s.activeGitHub == login) { [weak self] in self?.app.setActiveGitHub(login) }
            row.addArrangedSubview(smallButton("identity") { [weak self] in self?.showIdentityForm(login) })
            stack.addArrangedSubview(row)
        }
        stack.addArrangedSubview(linkButton("+ Add GitHub account") { [weak self] in
            self?.window?.close()
            self?.app.openPane(running: "gh auth login --hostname github.com --git-protocol https --web")
        })

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionTitle("VERCEL"))
        if s.vercelLabels.isEmpty { stack.addArrangedSubview(note("No Vercel accounts yet.")) }
        for label in s.vercelLabels {
            let row = radioRow(label, selected: s.activeVercel == label) { [weak self] in self?.app.setActiveVercel(label) }
            row.addArrangedSubview(smallButton("remove") { [weak self] in self?.app.removeVercel(label) })
            stack.addArrangedSubview(row)
        }
        stack.addArrangedSubview(linkButton("+ Add Vercel account") { [weak self] in self?.showVercelForm() })

        if let form { stack.addArrangedSubview(form) }
        stack.addArrangedSubview(spacer(6))
        stack.addArrangedSubview(note("Applies to new terminals. SSH remotes ignore the GitHub token."))
    }

    // MARK: Forms

    private func showVercelForm() {
        let label = field("Label (e.g. personal)")
        let token = NSSecureTextField()
        style(token, placeholder: "Token from vercel.com/account/tokens")
        let error = note("")
        error.textColor = Theme.danger
        let save = smallButton("Save") { [weak self] in
            let l = label.stringValue.trimmingCharacters(in: .whitespaces)
            let t = token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !l.isEmpty, !t.isEmpty else { error.stringValue = "Label and token are both needed."; return }
            error.stringValue = "Checking with Vercel…"
            self?.app.addVercel(label: l, token: t) { ok in
                if ok { self?.form = nil; self?.rebuild() } else { error.stringValue = "Token rejected by Vercel." }
            }
        }
        let cancel = smallButton("Cancel") { [weak self] in self?.form = nil; self?.rebuild() }
        form = formBox([label, token, hstack([save, cancel]), error])
        rebuild()
        window?.makeFirstResponder(label)
    }

    private func showIdentityForm(_ login: String) {
        let current = app.settings.identities[login]
        let name = field("Commit name")
        name.stringValue = current?.name ?? ""
        let email = field("Commit email")
        email.stringValue = current?.email ?? ""
        let save = smallButton("Save") { [weak self] in
            self?.app.setIdentity(GitHubIdentity(login: login, name: name.stringValue, email: email.stringValue))
            self?.form = nil
            self?.rebuild()
        }
        let cancel = smallButton("Cancel") { [weak self] in self?.form = nil; self?.rebuild() }
        form = formBox([note("Commits as \(login):"), name, email, hstack([save, cancel])])
        rebuild()
    }

    // MARK: Pieces

    private func sectionTitle(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = Theme.ui(10.5, .bold)
        l.textColor = Theme.muted
        return l
    }

    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = Theme.ui(11)
        l.textColor = Theme.muted
        l.preferredMaxLayoutWidth = width - 28
        return l
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    private func radioRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> NSStackView {
        let b = ActionButton(title: (selected ? "●  " : "○  ") + title, action: action)
        b.normalColor = selected ? Theme.headerTextFocused : Theme.headerText
        b.fontSize = 12.5
        b.alignment = .left
        let row = hstack([b])
        row.distribution = .fill
        b.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.widthAnchor.constraint(equalToConstant: width - 28).isActive = true
        return row
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> ActionButton {
        let b = ActionButton(title: title, action: action)
        b.fontSize = 11
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> ActionButton {
        let b = ActionButton(title: title, action: action)
        b.normalColor = Theme.accent
        b.fontSize = 12
        return b
    }

    private func field(_ placeholder: String) -> NSTextField {
        let f = NSTextField()
        style(f, placeholder: placeholder)
        return f
    }

    private func style(_ f: NSTextField, placeholder: String) {
        f.placeholderString = placeholder
        f.font = Theme.ui(12)
        f.textColor = Theme.headerTextFocused
        f.backgroundColor = Theme.hex(0x0c0c0c)
        f.isBordered = true
        f.focusRingType = .none
        f.widthAnchor.constraint(equalToConstant: width - 40).isActive = true
    }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        return s
    }

    private func formBox(_ views: [NSView]) -> NSView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        s.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        s.wantsLayer = true
        s.layer?.backgroundColor = Theme.hex(0x111111).cgColor
        s.layer?.cornerRadius = 6
        return s
    }
}

/// HoverButton that runs a closure.
final class ActionButton: NSButton {
    private let run: () -> Void
    var normalColor = Theme.headerText { didSet { refresh() } }
    var fontSize: CGFloat = 12 { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }

    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .none
        target = self
        self.action = #selector(fire)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var title: String { didSet { refresh() } }

    @objc private func fire() { run() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func refresh() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: hovering ? Theme.headerTextFocused : normalColor,
            .font: Theme.ui(fontSize, .medium),
        ])
    }
}

/// Top-bar chip: `● gh: <login> · ▲ <vercel>`; opens the accounts popover.
final class AccountsChip: NSButton {
    private let app: AppDelegate
    private var popover: NSPopover?

    init(app: AppDelegate) {
        self.app = app
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(open)
        toolTip = "Accounts for new terminals"
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .onyxAccountsChanged, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc func refresh() {
        let s = app.settings
        let hasGitHub = app.accountVars["GH_TOKEN"] != nil
        let text = NSMutableAttributedString()
        func add(_ str: String, _ color: NSColor) {
            text.append(NSAttributedString(string: str, attributes: [.foregroundColor: color, .font: Theme.ui(11, .medium)]))
        }
        add("● ", hasGitHub ? Theme.accent : Theme.danger)
        add("gh: \(hasGitHub ? (s.activeGitHub ?? "none") : "none")", hasGitHub ? Theme.headerText : Theme.danger)
        add("  ·  ▲ ", Theme.muted)
        add(app.accountVars["VERCEL_TOKEN"] != nil ? (s.activeVercel ?? "none") : "none", Theme.headerText)
        attributedTitle = text
        superview?.needsLayout = true
        (window?.windowController as? WindowController)?.relayoutTopBar()
    }

    @objc private func open() {
        let p = NSPopover()
        p.behavior = .transient
        p.appearance = NSAppearance(named: .darkAqua)
        let vc = NSViewController()
        vc.view = AccountsPanel(app: app)
        p.contentViewController = vc
        p.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = p
    }
}
