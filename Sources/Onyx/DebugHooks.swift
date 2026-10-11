import AppKit

/// Test hooks, inert unless their env vars are set:
/// - `ONYX_PANE_COMMAND`: run this instead of Claude in every pane.
/// - `ONYX_SNAPSHOT=<dir>` + `ONYX_SCRIPT="n n n w2 s"`: after launch run the steps
///   (`n` new pane, `p`/`P` wait 0.8 s/10 s, `t<i>` type $ONYX_TYPE_<i> into pane i, `w<i>` close pane i of the last window, `s` snapshot every window to
///   `<dir>/<step>-<window>.png`), then quit.
@MainActor
enum DebugHooks {
    static let env = ProcessInfo.processInfo.environment
    static var paneCommand: String? { env["ONYX_PANE_COMMAND"] }

    static func runScriptIfAny(_ app: AppDelegate) {
        guard let dir = env["ONYX_SNAPSHOT"], let script = env["ONYX_SCRIPT"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let steps = script.split(separator: " ").map(String.init)
        var i = 0
        func next() {
            guard i < steps.count else { NSApp.terminate(nil); return }
            let step = steps[i]
            i += 1
            switch step.first {
            case "n": app.newPane(nil)
            case "w": if let k = Int(step.dropFirst()) { app.closePane(at: k) }
            case "s": app.snapshot(to: dir, step: i)
            case "a": app.showSettings(nil)
            case "t": if let k = Int(step.dropFirst()), let text = env["ONYX_TYPE_\(k)"] { app.type(text, intoPane: k) }
            case "g": app.setActiveGitHub(String(step.dropFirst()))
            case "d": app.dragFirstDivider(by: Double(step.dropFirst()) ?? 100)
            default: break
            }
            let delay = step == "s" ? 0.2 : step == "P" ? 10 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: next)
    }
}

extension AppDelegate {
    func closePane(at index: Int) {
        guard let c = windowControllers.last, c.panes.indices.contains(index) else { return }
        c.close(c.panes[index])
    }

    /// Types `text` into pane `index` of the last window, then presses Return.
    func type(_ text: String, intoPane index: Int) {
        guard let c = windowControllers.last, c.panes.indices.contains(index) else { return }
        let t = c.panes[index].terminal
        t.send(txt: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { t.send(txt: "\r") }
    }

    /// Drags the divider right of the first pane horizontally by `dx` points.
    func dragFirstDivider(by dx: Double) {
        guard let c = windowControllers.last, let w = c.window, let first = c.panes.first else { return }
        let gridPoint = CGPoint(x: first.frame.maxX + 0.5, y: first.frame.midY)
        let start = c.grid.convert(gridPoint, to: nil)
        func ev(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        c.grid.mouseDown(with: ev(.leftMouseDown, start))
        c.grid.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: start.x + dx, y: start.y)))
        c.grid.mouseUp(with: ev(.leftMouseUp, CGPoint(x: start.x + dx, y: start.y)))
        c.grid.layoutSubtreeIfNeeded()
    }

    func snapshot(to dir: String, step: Int) {
        if let v = NSApp.windows.first(where: { $0.title == "Onyx Settings" && $0.isVisible })?.contentView,
           let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(step)-settings.png"))
        }
        for (w, c) in windowControllers.enumerated() {
            guard let view = c.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let summary = c.panes.map { p in
                let f = p.frame
                return "[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))]"
            }.joined(separator: " ")
            print("snapshot step \(step) window \(w): \(c.panes.count) panes \(summary)")
            for (i, p) in c.panes.enumerated() { print("  pane \(i): \(p.visibleText().suffix(4))") }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(step)-\(w).png"))
        }
    }
}
