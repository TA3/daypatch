// DayPatch's state and actions, shared by the menu bar item and the window.
import AppKit

enum MenuBarMode: String, CaseIterable, Identifiable {
    case always, whenNeeded, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: return "Always"
        case .whenNeeded: return "When Needed"
        case .never: return "Never"
        }
    }
}

struct Health {
    var checks: [(name: String, ok: Bool)]
    var diaVersion: String
    var date: String
    var failures: Int { checks.filter { !$0.ok }.count }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/daypatch/health.json")
    }

    static func load() -> Health? {
        guard let d = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let c = j["checks"] as? [String: Any] else { return nil }
        let checks = c.map { (name: $0.key, ok: ($0.value as? NSNumber)?.boolValue ?? false) }.sorted { $0.name < $1.name }
        return Health(checks: checks, diaVersion: j["diaVersion"] as? String ?? "?", date: j["date"] as? String ?? "")
    }
}

enum Prefs {
    static let d = UserDefaults.standard
    static var autoRepatch: Bool {
        get { d.object(forKey: "autoRepatch") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoRepatch") }
    }
    static var menuBarMode: MenuBarMode {
        get { MenuBarMode(rawValue: d.string(forKey: "menuBarMode") ?? "") ?? .whenNeeded }
        set { d.set(newValue.rawValue, forKey: "menuBarMode") }
    }
    static var autoUpdateSelf: Bool {
        get { d.object(forKey: "autoUpdateSelf") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoUpdateSelf") }
    }
    static var lastSelfUpdateCheck: Double {
        get { d.double(forKey: "lastSelfUpdateCheck") }
        set { d.set(newValue, forKey: "lastSelfUpdateCheck") }
    }
    /// Newer DayPatch version seen on GitHub and not installed yet (for attention).
    static var availableSelfVersion: String? {
        get { d.string(forKey: "availableSelfVersion").flatMap { SelfUpdater.isNewer($0, than: SelfUpdater.currentVersion) ? $0 : nil } }
        set { d.set(newValue, forKey: "availableSelfVersion") }
    }
    /// A broken-feature report the user has seen and dismissed (by its date).
    static var dismissedHealthDate: String? {
        get { d.string(forKey: "dismissedHealthDate") }
        set { d.set(newValue, forKey: "dismissedHealthDate") }
    }
}

/// Why DayPatch wants the user's attention, if at all. Shared with the background job.
func attentionReason(status: PatchStatus, lastError: String?, health: Health?) -> String? {
    if let e = lastError { return e }
    if let h = health, h.failures > 0, h.date != Prefs.dismissedHealthDate {
        return "\(h.failures) feature\(h.failures == 1 ? "" : "s") stopped working"
    }
    if case .needsPatch = status.state, PatchEngine.patchedIsRunning || !Prefs.autoRepatch {
        return "Quit \(PatchEngine.targetName) to finish patching"
    }
    if let v = Prefs.availableSelfVersion, !Prefs.autoUpdateSelf {
        return "DayPatch \(v) is available"
    }
    return nil
}

@MainActor
final class Controller: ObservableObject {
    let engine = PatchEngine(resources: Bundle.main.resourceURL!)

    @Published private(set) var status: PatchStatus
    @Published private(set) var busy: String?
    @Published private(set) var lastError: String?
    @Published private(set) var health: Health?
    @Published private(set) var pendingRepatch = false

    // Settings, mirrored for SwiftUI bindings.
    @Published var autoRepatch = Prefs.autoRepatch { didSet { Prefs.autoRepatch = autoRepatch; tick() } }
    @Published var autoUpdateSelf = Prefs.autoUpdateSelf { didSet { Prefs.autoUpdateSelf = autoUpdateSelf; onChange?() } }
    @Published private(set) var selfUpdate: DayPatchRelease?
    @Published private(set) var selfUpdateResult: String?
    @Published private(set) var selfUpdateChecking = false
    @Published var openAtLogin = LoginItem.isEnabled { didSet { LoginItem.set(openAtLogin && menuBarMode == .always) } }
    @Published var menuBarMode = Prefs.menuBarMode { didSet { applyMode() } }
    /// Patch /Applications/Dia.app itself (default) rather than a separate copy.
    var patchInPlace: Bool { PatchEngine.mode == .inPlace }

    /// Called whenever anything changes (status item refresh).
    var onChange: (() -> Void)?

    init() {
        status = engine.status()
        health = Health.load()
    }

    var attention: String? { attentionReason(status: status, lastError: lastError, health: health) }

    var statusLine: String {
        switch status.state {
        case .diaMissing: return "Dia isn't installed in /Applications"
        case .notInstalled: return patchInPlace ? "Dia isn't patched yet" : "Not built yet"
        case .restored: return "Original Dia restored — patch to use \(PatchEngine.appName)"
        case .upToDate: return "\(PatchEngine.appName) · Dia \(status.diaVersion ?? "")"
        case .needsPatch(let why): return "Needs patching: \(why)" + (pendingRepatch ? " — waiting for \(PatchEngine.targetName) to quit" : "")
        }
    }

    func refresh() {
        status = engine.status()
        health = Health.load()
        onChange?()
    }

    // MARK: Modes

    /// Always: the app stays running. When Needed / Never: a background job does the work.
    func applyMode() {
        Prefs.menuBarMode = menuBarMode
        if menuBarMode == .always {
            BackgroundAgent.uninstall()
            LoginItem.set(openAtLogin)
        } else {
            LoginItem.set(false)   // the background job runs at login instead
            BackgroundAgent.install()
        }
        onChange?()
    }

    // MARK: Automation

    func tick() {
        refresh()
        guard busy == nil else { return }
        if Date().timeIntervalSince1970 - Prefs.lastSelfUpdateCheck > 24 * 3600 { checkSelfUpdate() }
        if case .needsPatch = status.state, autoRepatch || pendingRepatch {
            if PatchEngine.patchedIsRunning { pendingRepatch = true } else { repatch(auto: true) }
        }
        onChange?()
    }

    /// Dia updates itself. In place, Dia ✦ keeps Dia's own updater; this is the fallback:
    /// put the original Dia back, open it to update, and re-patch once it quits.
    /// In copy mode: open the regular Dia; DayPatch re-patches from the new version.
    @Published private(set) var updateHint: String?

    func updateDia() {
        guard busy == nil else { return }
        if PatchEngine.patchedIsRunning {
            updateHint = "Quit \(PatchEngine.targetName) first" + (patchInPlace ? "." : " — both share one profile.")
            return
        }
        updateHint = "In Dia, choose Dia ▸ Check for Updates. Quit Dia when it's done; DayPatch re-patches automatically."
        guard patchInPlace else {
            NSWorkspace.shared.openApplication(at: PatchEngine.source, configuration: .init())
            return
        }
        run("Restoring the original Dia…", { try $0.restoreOriginal(); PatchEngine.restoredByUser = false }) { ok in
            guard ok else { return }
            self.pendingRepatch = true
            NSWorkspace.shared.openApplication(at: PatchEngine.source, configuration: .init())
        }
    }

    /// Puts the untouched Dia back; DayPatch leaves it alone until Patch is clicked.
    func restoreOriginal() {
        if PatchEngine.diaIsRunning { lastError = "Quit Dia first."; refresh(); return }
        run("Restoring the original Dia…", { try $0.restoreOriginal() }) { _ in }
    }

    func setPatchInPlace(_ on: Bool) {
        let mode: PatchMode = on ? .inPlace : .copy
        guard mode != PatchEngine.mode else { return }
        if PatchEngine.diaIsRunning || PatchEngine.isRunning(PatchEngine.copyDestination) {
            lastError = "Quit Dia first, then switch."
            refresh()
            return
        }
        run(on ? "Patching Dia directly…" : "Restoring Dia and building \(PatchEngine.appName)…", { try $0.switchMode(to: mode) }) { ok in
            if ok { Migration.trashOldApps() }
        }
    }

    /// Runs an engine job off the main thread, showing `label` while it works.
    private func run(_ label: String, _ job: @escaping @Sendable (PatchEngine) throws -> Void, then: @escaping (Bool) -> Void) {
        guard busy == nil else { return }
        busy = label
        onChange?()
        let engine = self.engine
        Task.detached {
            let result = Result { try job(engine) }
            await MainActor.run {
                self.busy = nil
                switch result {
                case .success: self.lastError = nil
                case .failure(let e): self.lastError = e.localizedDescription
                }
                then(result.isSuccess)
                self.refresh()
            }
        }
    }

    func repatch(auto: Bool = false) {
        guard busy == nil else { return }
        if PatchEngine.patchedIsRunning {
            pendingRepatch = true
            if !auto { notifyUser("Quit \(PatchEngine.targetName) to finish patching", "DayPatch will patch it as soon as it closes.") }
            onChange?()
            return
        }
        busy = "Patching…"
        onChange?()
        let reason: String = { if case .needsPatch(let r) = status.state { return r }; return "Rebuilt" }()
        let engine = self.engine
        Task.detached {
            let result = Result { try engine.patch() }
            await MainActor.run {
                self.busy = nil
                self.pendingRepatch = false
                switch result {
                case .success:
                    self.lastError = nil
                    Migration.trashOldApps()
                    if auto { notifyUser("\(PatchEngine.appName) is ready", "\(reason) — patched for Dia \(PatchEngine.version(PatchEngine.source) ?? "").") }
                case .failure(PatchError.busy):
                    break
                case .failure(let e):
                    self.lastError = e.localizedDescription
                    notifyUser("Couldn't patch Dia", e.localizedDescription)
                }
                self.refresh()
            }
        }
    }

    // MARK: Updating DayPatch itself

    func checkSelfUpdate(manual: Bool = false) {
        guard !selfUpdateChecking else { return }
        selfUpdateChecking = true
        Task {
            do {
                let r = try await SelfUpdater.latest()
                Prefs.lastSelfUpdateCheck = Date().timeIntervalSince1970
                selfUpdate = r
                Prefs.availableSelfVersion = r?.version
                selfUpdateResult = r.map { "DayPatch \($0.version) is available" } ?? "DayPatch \(SelfUpdater.currentVersion) is the latest"
                if let r, Prefs.autoUpdateSelf, !manual { installSelfUpdate(r) }
            } catch {
                selfUpdateResult = error.localizedDescription
            }
            selfUpdateChecking = false
            onChange?()
        }
    }

    func installSelfUpdate(_ r: DayPatchRelease) {
        guard busy == nil else { return }
        busy = "Updating DayPatch to \(r.version)…"
        onChange?()
        Task {
            do {
                try await SelfUpdater.install(r)
                Prefs.availableSelfVersion = nil
                notifyUser("DayPatch updated to \(r.version)", "\(PatchEngine.appName) will be re-patched with it.")
                SelfUpdater.relaunch()
                NSApp.terminate(nil)
            } catch {
                busy = nil
                lastError = error.localizedDescription
                refresh()
            }
        }
    }

    func dismissHealth() {
        Prefs.dismissedHealthDate = health?.date
        refresh()
    }

    func clearError() {
        lastError = nil
        refresh()
    }

    func openPatchedDia() {
        if !PatchEngine.isPatched(PatchEngine.destination) { repatch(); return }
        NSWorkspace.shared.openApplication(at: PatchEngine.destination, configuration: .init())
    }
}

extension Result { var isSuccess: Bool { if case .success = self { return true }; return false } }

func notifyUser(_ title: String, _ body: String) {
    Task { await notify(title, body) }
}
