import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Onyx")
        app.addItem(withTitle: "About Onyx", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Onyx", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Onyx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let shell = submenu(main, "Shell")
        shell.addItem(item("New Terminal", #selector(AppDelegate.newPane(_:)), "n"))
        shell.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n", [.command, .shift]))
        shell.addItem(.separator())
        shell.addItem(item("Close Terminal", #selector(AppDelegate.closePane(_:)), "w"))

        let edit = submenu(main, "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = submenu(main, "View")
        view.addItem(item("Bigger", #selector(AppDelegate.biggerFont(_:)), "="))
        view.addItem(item("Smaller", #selector(AppDelegate.smallerFont(_:)), "-"))
        view.addItem(.separator())
        for i in 0..<6 {
            let it = item("Terminal \(i + 1)", #selector(AppDelegate.focusPane(_:)), "\(i + 1)")
            it.tag = i
            view.addItem(it)
        }
        view.addItem(.separator())
        let arrows: [(String, Int)] = [("Left", NSLeftArrowFunctionKey), ("Right", NSRightArrowFunctionKey),
                                       ("Up", NSUpArrowFunctionKey), ("Down", NSDownArrowFunctionKey)]
        for (i, (name, key)) in arrows.enumerated() {
            let it = item("Focus \(name)", #selector(AppDelegate.moveFocus(_:)), String(Character(UnicodeScalar(key)!)), [.command, .option])
            it.tag = i
            view.addItem(it)
        }

        let window = submenu(main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        return it
    }
}
