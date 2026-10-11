import AppKit
import OnyxCore

/// Test hooks, inert unless their env vars are set:
/// - `ONYX_PANE_COMMAND`: run this instead of Claude in every pane.
/// - `ONYX_SNAPSHOT=<dir>` + `ONYX_SCRIPT="n n n w2 s"`: after launch run the steps
///   (`n` new pane, `p`/`P` wait 0.8 s/10 s, `t<i>` type $ONYX_TYPE_<i> into pane i, `w<i>` close pane i of the last window, `s` snapshot every window to
///   `<dir>/<step>-<window>.png`), then quit.
@MainActor
enum DebugHooks {
    static let env = ProcessInfo.processInfo.environment
    static var paneCommand: String? { env["ONYX_PANE_COMMAND"] }
    static var mark: (Double, TimeInterval)?

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
            case "t": if let k = Int(step.dropFirst()), let text = env["ONYX_TYPE_\(k)"] { app.type(text, intoPane: k) }
            case "k":  // k<pane>.<text id>: type $ONYX_TYPE_<text id> into <pane> as key events
                let parts = step.dropFirst().split(separator: ".")
                if parts.count == 2, let k = Int(parts[0]), let text = env["ONYX_TYPE_\(parts[1])"] { app.keyType(text, intoPane: k) }
            case "c": if let k = Int(step.dropFirst()) { app.keyControl("c", intoPane: k) }
            case "z": if let k = Int(step.dropFirst()) { app.keyControl("z", intoPane: k) }
            case "K": app.clearPane(nil)
            case "+": app.biggerFont(nil)
            case "-": app.smallerFont(nil)
            case "m": app.measure(dir: dir)
            case "V": if let k = Int(step.dropFirst()) { app.pasteInto(pane: k) }
            case "r": app.resizeLast(to: CGSize(width: 900, height: 560))
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

    func report(_ dir: String, _ line: String) {
        print(line)
        let url = URL(fileURLWithPath: dir + "/report.txt")
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }

    /// Types `text` as real key events (the keyboard path), "\n" pressing Return.
    func keyType(_ text: String, intoPane index: Int) {
        guard let c = windowControllers.last, c.panes.indices.contains(index), let w = c.window else { return }
        c.panes[index].focus()
        for ch in text {
            let isReturn = ch == "\n"
            let chars = isReturn ? "\r" : String(ch)
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: isReturn ? 36 : 0) {
                w.sendEvent(e)
            }
        }
    }

    func keyControl(_ letter: Character, intoPane index: Int) {
        guard let c = windowControllers.last, c.panes.indices.contains(index), let w = c.window,
              let code = letter.asciiValue else { return }
        c.panes[index].focus()
        let keyCodes: [Character: UInt16] = ["c": 8, "z": 6]
        if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control], timestamp: 0,
                                    windowNumber: w.windowNumber, context: nil,
                                    characters: String(UnicodeScalar(code - 96)),
                                    charactersIgnoringModifiers: String(letter), isARepeat: false, keyCode: keyCodes[letter] ?? 0) {
            w.sendEvent(e)
        }
    }

    /// Puts $ONYX_PASTE on the pasteboard and pastes it into pane `index` via the Edit menu path.
    func pasteInto(pane index: Int) {
        guard let c = windowControllers.last, c.panes.indices.contains(index) else { return }
        let saved = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DebugHooks.env["ONYX_PASTE"] ?? "", forType: .string)
        c.panes[index].focus()
        // Straight to the focused terminal: during scripted runs Onyx is not the active app, so
        // there is no key window for NSApp.sendAction to route through.
        _ = c.window?.firstResponder?.tryToPerform(#selector(NSText.paste(_:)), with: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSPasteboard.general.clearContents()
            if let saved { NSPasteboard.general.setString(saved, forType: .string) }
        }
    }

    /// First call marks a start; each later call reports the app's CPU use since then and its memory.
    func measure(dir: String) {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        let cpu = Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        let now = ProcessInfo.processInfo.systemUptime
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        if let (cpu0, t0) = DebugHooks.mark {
            var vm = task_vm_info_data_t()
            var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            _ = withUnsafeMutablePointer(to: &vm) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount) }
            }
            report(dir, String(format: "measure: app CPU %.1f%% over %.0f s, RSS %.0f MB, footprint %.0f MB", (cpu - cpu0) / (now - t0) * 100, now - t0,
                               Double(info.resident_size) / 1_048_576, Double(vm.phys_footprint) / 1_048_576))
        }
        DebugHooks.mark = (cpu, now)
    }

    func resizeLast(to size: CGSize) {
        guard let w = windowControllers.last?.window else { return }
        w.setFrame(NSRect(origin: w.frame.origin, size: size), display: true)
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
        for (w, c) in windowControllers.enumerated() {
            guard let view = c.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let summary = c.panes.map { p in
                let f = p.frame
                return "[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))]"
            }.joined(separator: " ")
            report(dir, "snapshot step \(step) window \(w): \(c.panes.count) panes \(summary)")
            for (i, p) in c.panes.enumerated() {
                let t = p.getTerminalSize()
                report(dir, "  pane \(i) title=[\(p.headerTitle)] running=\(p.terminal.process.running) busy=\(p.isBusy) size=\(t.cols)x\(t.rows) lines=\(t.lines): \(p.visibleText().suffix(Int(DebugHooks.env["ONYX_LINES"] ?? "2") ?? 2))")
            }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(step)-\(w).png"))
        }
    }
}
