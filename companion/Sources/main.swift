// DayPatch: keeps Dia ✦ patched.
//  - Patches Dia itself (or, optionally, a separate copy) and re-patches when Dia
//    (or daypatch itself) changes.
//  - Dia updates itself as usual; DayPatch re-patches afterwards.
//  - Shows which daypatch features still work after a Dia update.
// Opening the app shows its window. The menu bar icon is Always / When Needed / Never.
import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private let c = Controller()
    private let launchedForAttention = CommandLine.arguments.contains("--attention")
    private let launchedAtLogin = CommandLine.arguments.contains("--login")

    func applicationDidFinishLaunching(_ n: Notification) {
        if Migration.run() { c.applyMode() }   // re-create the old background job under the new name
        Migration.trashOldApps()
        Migration.mergeSplitProfiles()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        c.onChange = { [weak self] in self?.refresh() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        // Re-check when Dia or Dia ✦ quits (that's when patching/updating is possible).
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "company.thebrowser.dia" else { return }
            MainActor.assumeIsolated { self?.c.tick() }
        }
        let local = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.c.tick() } }
        local.tolerance = 30

        // First launch: set up the background job for the default mode.
        if UserDefaults.standard.string(forKey: "menuBarMode") == nil { c.applyMode() }

        Handoff.shared.onFinish = { [weak self] in self?.refresh() }
        c.tick()
        // Launched to open a daypatch:// link (the passkey handoff): no window.
        let openedForURL = (n.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) == false
        if !launchedForAttention && !launchedAtLogin && !openedForURL { showWindow() }
        refresh()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "daypatch" && url.host == "handoff" { Handoff.shared.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Visibility

    private var iconWanted: Bool {
        switch c.menuBarMode {
        case .always: return true
        case .whenNeeded: return c.attention != nil || c.busy != nil
        case .never: return false
        }
    }

    private func refresh() {
        statusItem.isVisible = iconWanted
        statusItem.button?.image = DayPatchIcon.menuBarImage(c.busy != nil ? .busy : (c.attention != nil ? .attention : .none))
        statusItem.button?.toolTip = c.attention.map { "DayPatch — \($0)" } ?? "DayPatch"
        quitIfIdle()
    }

    /// Outside "Always", DayPatch only runs while it has something to show.
    private func quitIfIdle() {
        guard c.menuBarMode != .always, c.busy == nil, !iconWanted, window?.isVisible != true, !Handoff.shared.isActive else { return }
        // Let any pending work (e.g. a just-started update check) settle first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.c.menuBarMode != .always, self.c.busy == nil, !self.iconWanted, self.window?.isVisible != true,
                  !Handoff.shared.isActive else { return }
            NSApp.terminate(nil)
        }
    }

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: DayPatchWindowView(c: c)))
            w.title = "DayPatch"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        c.refresh()
        NSApp.setActivationPolicy(.regular)   // Dock icon + ⌘Tab while the window is open
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { self.quitIfIdle() }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        actions = [:]
        menu.addItem(header("DayPatch"))
        menu.addItem(info(c.busy ?? c.statusLine))
        if let a = c.attention { menu.addItem(info("⚠︎ \(a)")) }
        menu.addItem(.separator())
        menu.addItem(item("Open \(PatchEngine.appName)", "o") { $0.c.openPatchedDia() })
        if let r = c.selfUpdate {
            menu.addItem(item("Update DayPatch to \(r.version)", "") { $0.c.installSelfUpdate(r) })
        }
        menu.addItem(item("Update Dia…", "u") { $0.c.updateDia(); $0.showWindow() })
        let patch = item(c.status.isUpToDate ? "Rebuild \(PatchEngine.appName)" : "Patch Now", "p") { $0.c.repatch() }
        patch.isEnabled = c.busy == nil
        menu.addItem(patch)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", ",") { $0.showWindow() })
        menu.addItem(item("DayPatch on GitHub", "") { _ in NSWorkspace.shared.open(URL(string: "https://github.com/\(SelfUpdater.repo)")!) })
        menu.addItem(item("Quit DayPatch", "q") { _ in NSApp.terminate(nil) })
    }

    private func header(_ s: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
        i.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        return i
    }
    private func info(_ s: String) -> NSMenuItem { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }

    private var actions: [Int: (AppDelegate) -> Void] = [:]
    private func item(_ title: String, _ key: String, _ run: @escaping (AppDelegate) -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: key)
        i.target = self
        i.tag = actions.count
        actions[i.tag] = run
        return i
    }
    @objc private func runMenuAction(_ sender: NSMenuItem) { actions[sender.tag]?(self) }
}

// Diagnostics: DayPatch.app/Contents/MacOS/DayPatch --status | --patch | --background-check | ...
let cliFlags: Set<String> = ["--status", "--patch", "--update-from", "--background-check", "--background-mode", "--make-icon", "--restore", "--mode", "--help"]
if let flag = CommandLine.arguments.dropFirst().first, cliFlags.contains(flag) {
    let engine = PatchEngine(resources: Bundle.main.resourceURL!)
    let done = DispatchSemaphore(value: 0)
    Task {
        defer { done.signal() }
        do {
            switch flag {
            case "--status":
                let s = engine.status()
                print("mode: \(PatchEngine.mode.rawValue)  target: \(PatchEngine.destination.path)  running: \(PatchEngine.patchedIsRunning)  Dia running: \(PatchEngine.diaIsRunning)")
                print("Dia: \(s.diaVersion ?? "missing")  Dia ✦: \(s.patchedFrom ?? "not built")  patch: \(engine.patchVersion)  state: \(s.state)  menu bar: \(Prefs.menuBarMode.rawValue)  background job: \(BackgroundAgent.isInstalled)")
            case "--background-mode":
                let on = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "on"
                if on { LoginItem.set(false); BackgroundAgent.install() } else { BackgroundAgent.uninstall() }
                print("Background mode \(on ? "on" : "off")")
            case "--update-from":
                // Dev: install a specific signed build, e.g. from a local server.
                let a = CommandLine.arguments
                guard a.count == 4, let zip = URL(string: a[2]), let sig = URL(string: a[2] + ".sig") else { print("usage: --update-from <zip-url> <version>"); break }
                try await SelfUpdater.install(DayPatchRelease(version: a[3], zip: zip, signature: sig, notesURL: nil))
                print("Installed DayPatch \(a[3]) at \(Bundle.main.bundlePath)")
            case "--background-check":
                await runBackgroundCheck()
            case "--make-icon":
                try DayPatchIcon.writeICNS(to: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."))
            case "--restore":
                try engine.restoreOriginal()
                print("Restored: \(PatchEngine.version(PatchEngine.source) ?? "?")")
            case "--mode":
                guard CommandLine.arguments.count > 2, let m = PatchMode(rawValue: CommandLine.arguments[2]) else { print("usage: --mode inPlace|copy"); break }
                try engine.switchMode(to: m)
                print("Mode: \(PatchEngine.mode.rawValue)")
            case "--patch":
                try engine.patch()
                print("Patched: \(PatchEngine.version(PatchEngine.destination) ?? "?")")
            default:
                print("usage: DayPatch [--status | --patch | --restore | --mode inPlace|copy | --background-check | --background-mode on|off]")
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }
    done.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
