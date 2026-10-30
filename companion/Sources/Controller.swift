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
        return "Quit Patched Dia to finish patching"
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
        case .notInstalled: return "Not built yet"
        case .upToDate: return "Patched for Dia \(status.diaVersion ?? "")"
        case .needsPatch(let why): return "Needs patching: \(why)" + (pendingRepatch ? " — waiting for Patched Dia to quit" : "")
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

    /// Dia updates itself: open the regular Dia (whose own updater checks and installs),
    /// and when it quits with a new version on disk, DayPatch re-patches from it.
    @Published private(set) var updateHint: String?

    func updateDia() {
        if PatchEngine.patchedIsRunning {
            updateHint = "Quit Patched Dia first — both share one profile."
            return
        }
        updateHint = "In Dia, choose Dia ▸ Check for Updates. Quit Dia when it's done; DayPatch re-patches automatically."
        NSWorkspace.shared.openApplication(at: PatchEngine.source, configuration: .init())
    }

    func repatch(auto: Bool = false) {
        guard busy == nil else { return }
        if PatchEngine.patchedIsRunning {
            pendingRepatch = true
            if !auto { notifyUser("Quit Patched Dia to finish patching", "DayPatch will rebuild it as soon as it closes.") }
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
                    if auto { notifyUser("Patched Dia is ready", "\(reason) — patched for Dia \(PatchEngine.version(PatchEngine.source) ?? "").") }
                case .failure(PatchError.busy):
                    break
                case .failure(let e):
                    self.lastError = e.localizedDescription
                    notifyUser("Couldn't patch Patched Dia", e.localizedDescription)
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
                notifyUser("DayPatch updated to \(r.version)", "Patched Dia will be re-patched with it.")
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
        if !FileManager.default.fileExists(atPath: PatchEngine.destination.path) { repatch(); return }
        NSWorkspace.shared.openApplication(at: PatchEngine.destination, configuration: .init())
    }
}

func notifyUser(_ title: String, _ body: String) {
    Task { await notify(title, body) }
}
