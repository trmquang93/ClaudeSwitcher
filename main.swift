import Cocoa

struct Profile: Codable {
    var title: String
    var dataDir: String?     // --user-data-dir (nil = the default Claude profile)
    var configDir: String?   // CLAUDE_CONFIG_DIR for Claude Code sessions
}

let claudeApp = "/Applications/Claude.app"
let home = NSHomeDirectory()
let storeURL: URL = {
    let dir = URL(fileURLWithPath: home + "/Library/Application Support/ClaudeSwitcher")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("accounts.json")
}()

func loadProfiles() -> [Profile] {
    if let d = try? Data(contentsOf: storeURL),
       let p = try? JSONDecoder().decode([Profile].self, from: d), !p.isEmpty { return p }
    return [
        Profile(title: "Claude", dataDir: nil, configDir: nil),
        Profile(title: "Claude Personal",
                dataDir: home + "/Library/Application Support/Claude-2",
                configDir: home + "/.claude-personal"),
    ]
}

func saveProfiles(_ p: [Profile]) {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
    try? enc.encode(p).write(to: storeURL)
}

/// Command lines of all running Claude main processes, keyed by pid.
func claudeProcesses() -> [(pid: pid_t, cmd: String)] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-axo", "pid=,command="]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    task.waitUntilExit()
    let bin = claudeApp + "/Contents/MacOS/Claude"
    var res: [(pid_t, String)] = []
    for line in out.split(separator: "\n") {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard let sp = s.firstIndex(of: " "), let id = pid_t(s[..<sp]) else { continue }
        let cmd = String(s[s.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
        guard cmd == bin || cmd.hasPrefix(bin + " ") else { continue }
        res.append((id, cmd))
    }
    return res
}

func pid(for p: Profile, in procs: [(pid: pid_t, cmd: String)]) -> pid_t? {
    for (id, cmd) in procs {
        if let d = p.dataDir {
            if cmd.contains("--user-data-dir=" + d) { return id }
        } else if !cmd.contains("--user-data-dir=") {
            return id
        }
    }
    return nil
}

func launch(_ p: Profile) {
    var args = ["-n"]
    if let c = p.configDir { args += ["--env", "CLAUDE_CONFIG_DIR=" + c] }
    args += ["-a", claudeApp]
    if let d = p.dataDir { args += ["--args", "--user-data-dir=" + d] }
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    t.arguments = args
    // `open` forwards its environment to the app. Drop any CLAUDE_CONFIG_DIR the Switcher
    // inherited, so a profile without a configDir uses the default ~/.claude.
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
    t.environment = env
    try? t.run()
}

/// Bring an account's Claude window forward, launching it first if it isn't running.
func openProfile(_ p: Profile) {
    if let id = pid(for: p, in: claudeProcesses()), let app = NSRunningApplication(processIdentifier: id) {
        if app.isHidden { app.unhide() }
        if #available(macOS 14, *) { app.activate() } else { app.activate(options: [.activateIgnoringOtherApps]) }
    } else {
        launch(p)
    }
}

extension NSBox {
    static func separatorLine() -> NSBox { let b = NSBox(); b.boxType = .separator; return b }
}

final class OptionRow: NSView {
    let t: String, on: Bool, act: () -> Void
    var hover = false { didSet { needsDisplay = true } }
    init(title: String, enabled: Bool, act: @escaping () -> Void) {
        t = title; on = enabled; self.act = act
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        if hover && on { NSColor.selectedContentBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill() }
        let c: NSColor = !on ? .disabledControlTextColor : (hover ? .selectedMenuItemTextColor : .labelColor)
        NSAttributedString(string: t, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: c]).draw(at: NSPoint(x: 10, y: 3))
    }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseUp(with e: NSEvent) { if on { act() } }
}

final class AccountRowView: NSView {
    let onOpen: () -> Void, onRename: () -> Void, onRemove: () -> Void
    let canRemove: Bool
    var hovering = false { didSet { needsDisplay = true; renderLabel(); more.contentTintColor = hovering ? .selectedMenuItemTextColor : .secondaryLabelColor } }
    let label = NSTextField(labelWithString: "")
    let more = NSButton()
    var title = "", running = false
    func renderLabel() {
        let t = NSMutableAttributedString(string: "● ", attributes: [
            .foregroundColor: running ? NSColor.systemGreen : NSColor.systemGray,
            .font: NSFont.menuFont(ofSize: 0)])
        t.append(NSAttributedString(string: title, attributes: [
            .foregroundColor: hovering ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
            .font: NSFont.menuFont(ofSize: 0)]))
        label.attributedStringValue = t
    }

    init(title: String, running: Bool, canRemove: Bool, onOpen: @escaping () -> Void, onRename: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.onOpen = onOpen; self.onRename = onRename; self.onRemove = onRemove; self.canRemove = canRemove
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        self.title = title; self.running = running
        renderLabel()
        label.frame = NSRect(x: 14, y: 2, width: 200, height: 18)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        more.bezelStyle = .regularSquare
        more.isBordered = false
        more.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
        more.contentTintColor = .secondaryLabelColor
        more.frame = NSRect(x: 228, y: 1, width: 24, height: 20)
        addSubview(more)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ r: NSRect) {
        guard hovering else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
    }
    /// The list is a panel, not an NSMenu, so a real menu can pop up from the "…" while the panel stays open.
    func showMore() {
        let m = NSMenu()
        let r = NSMenuItem(title: "Rename", action: #selector(doRename), keyEquivalent: ""); r.target = self; m.addItem(r)
        let d = NSMenuItem(title: "Remove", action: #selector(doRemove), keyEquivalent: ""); d.target = self; d.isEnabled = canRemove; m.addItem(d)
        m.popUp(positioning: nil, at: NSPoint(x: more.frame.maxX + 4, y: more.frame.maxY), in: self)
    }
    @objc func doRename() { onRename() }
    @objc func doRemove() { onRemove() }
    override func hitTest(_ p: NSPoint) -> NSView? { frame.contains(p) ? self : nil }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if more.frame.insetBy(dx: -4, dy: -2).contains(p) { showMore(); return }
        onOpen()
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Controller: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var profiles = loadProfiles()
    var panel: NSPanel?
    var monitors: [Any] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "Claude accounts")
            img?.isTemplate = true
            b.image = img
            b.toolTip = "Claude accounts"
            b.target = self; b.action = #selector(togglePanel)
        }
        saveProfiles(profiles)
    }

    @objc func togglePanel() { panel == nil ? showPanel() : closePanel() }

    func closePanel() {
        panel?.orderOut(nil); panel = nil
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors = []
        statusItem.button?.highlight(false)
    }

    /// Rebuilt on every open so the running markers are current.
    func showPanel() {
        let procs = claudeProcesses()
        let w: CGFloat = 260, rowH: CGFloat = 22
        var views: [NSView] = []
        for (i, p) in profiles.enumerated() {
            let canRemove = profiles.count > 1 && p.dataDir != nil
            views.append(AccountRowView(
                title: p.title, running: pid(for: p, in: procs) != nil, canRemove: canRemove,
                onOpen: { [weak self] in self?.closePanel(); self?.open(i) },
                onRename: { [weak self] in self?.closePanel(); DispatchQueue.main.async { self?.renameAccount(i) } },
                onRemove: { [weak self] in self?.closePanel(); DispatchQueue.main.async { self?.removeAccount(i) } }))
        }
        views.append(NSBox.separatorLine())
        views.append(OptionRow(title: "+  Add Account…", enabled: true) { [weak self] in self?.closePanel(); DispatchQueue.main.async { self?.addAccount() } })
        views.append(NSBox.separatorLine())
        views.append(OptionRow(title: "Quit Claude Switcher", enabled: true) { NSApp.terminate(nil) })

        let heights = views.map { $0 is NSBox ? CGFloat(9) : rowH }
        let total = heights.reduce(0, +) + 10
        let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: total))
        fx.material = .menu; fx.state = .active; fx.wantsLayer = true; fx.layer?.cornerRadius = 10
        var y = total - 5
        for (v, h) in zip(views, heights) {
            y -= h
            v.frame = v is AccountRowView ? NSRect(x: 0, y: y, width: w, height: h) : (v is NSBox ? NSRect(x: 14, y: y + 4, width: w - 28, height: 1) : NSRect(x: 5, y: y, width: w - 10, height: h))
            fx.addSubview(v)
        }
        guard let bw = statusItem.button?.window else { return }
        let br = bw.frame
        let pnl = FloatingPanel(contentRect: NSRect(x: min(br.midX - w / 2, (bw.screen?.frame.maxX ?? br.maxX) - w - 8), y: br.minY - total - 4, width: w, height: total),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pnl.level = .popUpMenu; pnl.isOpaque = false; pnl.backgroundColor = .clear; pnl.hasShadow = true
        pnl.contentView = fx
        pnl.makeKeyAndOrderFront(nil)
        panel = pnl
        statusItem.button?.highlight(true)
        // Click anywhere outside the panel (and the status item) closes it.
        let outside: (NSEvent) -> Void = { [weak self] e in
            guard let self = self, let pnl = self.panel else { return }
            let loc = e.window == nil ? e.locationInWindow : (e.window!.convertPoint(toScreen: e.locationInWindow))
            if !pnl.frame.contains(loc), e.window !== self.statusItem.button?.window { self.closePanel() }
        }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { outside($0) }!)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { e in outside(e); return e }!)
    }

    func open(_ i: Int) { openProfile(profiles[i]) }

    @objc func addAccount() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add Claude account"
        alert.informativeText = "Name the account. Claude opens with a fresh profile; sign in once and it stays signed in."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "e.g. Work"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        var dataDir = home + "/Library/Application Support/Claude-" + slug
        var configDir = home + "/.claude-" + slug
        var n = 2
        while profiles.contains(where: { $0.dataDir == dataDir }) {
            dataDir = home + "/Library/Application Support/Claude-\(slug)-\(n)"
            configDir = home + "/.claude-\(slug)-\(n)"
            n += 1
        }
        let p = Profile(title: name, dataDir: dataDir, configDir: configDir)
        profiles.append(p)
        saveProfiles(profiles)
        launch(p)
    }

    /// Only the label changes; the profile is matched by its data dir, so it stays signed in.
    func renameAccount(_ i: Int) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rename “\(profiles[i].title)”"
        alert.informativeText = "Only the name in this menu changes."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = profiles[i].title
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        profiles[i].title = name
        saveProfiles(profiles)
    }

    func removeAccount(_ i: Int) {
        let p = profiles[i]
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove “\(p.title)” from the list?"
        alert.informativeText = "Its data stays on disk; only the menu entry is removed."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        profiles.remove(at: i)
        saveProfiles(profiles)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let ctl = Controller()
app.delegate = ctl
app.run()
