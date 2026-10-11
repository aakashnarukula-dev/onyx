import AppKit
import SwiftTerm

@MainActor enum Theme {
    static let background = NSColor.black
    static let foreground = hex(0xd4d4d4)
    static let cursor = NSColor.white
    static let cursorStyle = CursorStyle.blinkBar
    static let divider = hex(0x1a1a1a)
    static let dotIdle = hex(0x3a3a3a)
    static let borderIdle = hex(0x222222)
    static let headerText = hex(0x8a8a8a)
    static let headerTextFocused = hex(0xe6e6e6)
    static let muted = hex(0x6b6b6b)
    static let accent = hex(0xe8915f)
    static let danger = hex(0xa04040)
    static let headerHeight: CGFloat = 24
    static let topBarHeight: CGFloat = 30
    static let gap: CGFloat = 5         // between terminals
    static let margin: CGFloat = 5      // around the grid
    static let cornerRadius: CGFloat = 10
    static let padding: CGFloat = 6     // terminal text inset from a pane's sides and bottom
    static let minPane = CGSize(width: 200, height: 120)

    static func font(size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size, weight: weight) }

    /// ANSI 16 tuned for a pure black background.
    static let ansi: [SwiftTerm.Color] = [
        0x2e2e2e, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xd4d4d4,
        0x5c6370, 0xff7a85, 0xb5e08f, 0xf0d197, 0x82c4ff, 0xd79bf0, 0x7fd0da, 0xffffff,
    ].map { v in
        SwiftTerm.Color(red: UInt16((v >> 16) & 0xff) * 257, green: UInt16((v >> 8) & 0xff) * 257, blue: UInt16(v & 0xff) * 257)
    }

    static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
