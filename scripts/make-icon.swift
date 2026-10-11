// Draws Onyx's icon (black squircle, 3-pane grid outline) as a 1024 px PNG: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor.black.setFill()
NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).fill()
NSColor(white: 1, alpha: 0.10).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
rim.lineWidth = 6
rim.stroke()

// Grid: two stacked panes left, one tall pane right.
let g = body.insetBy(dx: 150, dy: 170)
let gap: CGFloat = 28
let leftW = (g.width - gap) / 2
let halfH = (g.height - gap) / 2
let panes = [
    NSRect(x: g.minX, y: g.minY + halfH + gap, width: leftW, height: halfH),
    NSRect(x: g.minX, y: g.minY, width: leftW, height: halfH),
    NSRect(x: g.minX + leftW + gap, y: g.minY, width: leftW, height: g.height),
]
for (i, r) in panes.enumerated() {
    let p = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
    p.lineWidth = 14
    (i == 2 ? NSColor(srgbRed: 0.91, green: 0.57, blue: 0.37, alpha: 1) : NSColor(white: 0.85, alpha: 1)).setStroke()
    p.stroke()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
