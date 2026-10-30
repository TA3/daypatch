// Background mode: no menu bar icon, no running app. A launchd job runs
// `DayPatch --background-check` when Dia changes (e.g. it updated itself), every 30
// minutes, and right after Dia ✦ quits (the patch kicks the job). Each run
// re-patches if needed and exits.
import AppKit
import UserNotifications

enum BackgroundAgent {
    static let label = "dev.ta3.daypatch.watch"
    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    private static var domain: String { "gui/\(getuid())" }

    static func install() {
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath!, "--background-check"],
            "WatchPaths": [PatchEngine.source.appendingPathComponent("Contents/Info.plist").path],
            "StartInterval": 1800,
            "RunAtLoad": true,
            "ProcessType": "Background",
            "LowPriorityIO": true,
        ]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (agent as NSDictionary).write(to: plist, atomically: true)
        launchctl(["bootout", "\(domain)/\(label)"])
        launchctl(["bootstrap", domain, plist.path])
    }

    static func uninstall() {
        launchctl(["bootout", "\(domain)/\(label)"])
        try? FileManager.default.removeItem(at: plist)
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }
}

/// One background pass. Mirrors the menu bar app's automation.
func runBackgroundCheck() async {
    Migration.trashOldApps()
    Migration.mergeSplitProfiles()
    let engine = PatchEngine(resources: Bundle.main.resourceURL!)
    let autoRepatch = Prefs.autoRepatch

    // Kicked as Dia ✦ quits: give it a moment to finish exiting.
    for _ in 0..<30 where PatchEngine.patchedIsRunning { try? await Task.sleep(nanoseconds: 500_000_000) }

    if case .needsPatch(let why) = engine.status().state, autoRepatch, !PatchEngine.patchedIsRunning {
        do {
            try engine.patch()
            await notify("\(PatchEngine.appName) is ready", "\(why) — patched for Dia \(PatchEngine.version(PatchEngine.source) ?? "").")
        } catch PatchError.busy {
        } catch {
            await notify("Couldn't patch Dia", error.localizedDescription)
        }
    }

    // DayPatch's own updates: at most once a day.
    if Date().timeIntervalSince1970 - Prefs.lastSelfUpdateCheck > 24 * 3600, let r = try? await SelfUpdater.latest() {
        Prefs.lastSelfUpdateCheck = Date().timeIntervalSince1970
        Prefs.availableSelfVersion = r.version
        if Prefs.autoUpdateSelf {
            do {
                try await SelfUpdater.install(r)
                Prefs.availableSelfVersion = nil
                await notify("DayPatch updated to \(r.version)", "\(PatchEngine.appName) will be re-patched with it.")
                return   // the new DayPatch re-patches on its next run
            } catch {
                await notify("Couldn't update DayPatch", error.localizedDescription)
            }
        }
    } else if Date().timeIntervalSince1970 - Prefs.lastSelfUpdateCheck > 24 * 3600 {
        Prefs.lastSelfUpdateCheck = Date().timeIntervalSince1970   // no newer release
    }

    // "When Needed": bring up the menu bar icon if something is left for the user.
    if Prefs.menuBarMode == .whenNeeded,
       attentionReason(status: engine.status(), lastError: nil, health: Health.load()) != nil {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.arguments = ["--attention"]
        _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg)
    }
}

func notify(_ title: String, _ body: String) async {
    let c = UNMutableNotificationContent()
    c.title = title
    c.body = body
    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
}
