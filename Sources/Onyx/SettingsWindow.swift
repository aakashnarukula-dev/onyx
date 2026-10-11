import AppKit

/// ⌘, — font size plus the same account controls as the top-bar popover.
final class SettingsWindow: NSWindowController {
    private let app: AppDelegate
    private let sizeLabel = NSTextField(labelWithString: "")

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Onyx Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.background
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let title = NSTextField(labelWithString: "FONT SIZE")
        title.font = Theme.ui(10.5, .bold)
        title.textColor = Theme.muted
        sizeLabel.font = Theme.ui(12.5, .medium)
        sizeLabel.textColor = Theme.headerTextFocused
        let minus = ActionButton(title: "−") { [weak self] in self?.bump(-1) }
        let plus = ActionButton(title: "+") { [weak self] in self?.bump(1) }
        minus.fontSize = 15
        plus.fontSize = 15
        let fontRow = NSStackView(views: [title, NSView(), minus, sizeLabel, plus])
        fontRow.spacing = 10
        fontRow.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 0, right: 14)

        let root = NSStackView(views: [fontRow, AccountsPanel(app: app)])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 4
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.background.cgColor
        window.contentView = root
        fontRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        updateSize()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func bump(_ d: Double) {
        app.applyFontSize(app.fontSize + d)
        updateSize()
    }

    private func updateSize() { sizeLabel.stringValue = "\(Int(app.fontSize)) pt" }
}
