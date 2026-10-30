// One-time move from this project's previous name ("Arced"): preferences,
// launchd jobs and the old apps. Safe to call on every launch; it does nothing
// once the old pieces are gone.
import AppKit

enum Migration {
    private static let oldDomain = "dev.ta3.arced"
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let oldAgents = ["dev.ta3.arced.watch", "dev.ta3.arced"]
    private static let oldCompanion = home.appendingPathComponent("Applications/Arced.app")
    private static let oldPatched = [home.appendingPathComponent("Applications/Arced Dia.app"),
                                     home.appendingPathComponent("Applications/Patched Dia.app")]

    /// Returns true if the old background job existed (so the caller re-creates it under the new name).
    @discardableResult
    static func run() -> Bool {
        let d = UserDefaults.standard
        if d.object(forKey: "migratedFromArced") == nil, let old = UserDefaults(suiteName: oldDomain) {
            let keys = ["menuBarMode": "menuBarMode", "autoRepatch": "autoRepatch",
                        "autoUpdateArced": "autoUpdateSelf", "dismissedHealthDate": "dismissedHealthDate"]
            for (from, to) in keys where d.object(forKey: to) == nil {
                if let v = old.object(forKey: from) { d.set(v, forKey: to) }
            }
            d.set(true, forKey: "migratedFromArced")
        }

        var hadBackgroundJob = false
        for label in oldAgents {
            let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
            guard FileManager.default.fileExists(atPath: plist.path) else { continue }
            if label.hasSuffix(".watch") { hadBackgroundJob = true }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            try? FileManager.default.removeItem(at: plist)
        }
        return hadBackgroundJob
    }

    /// After Dia ✦ exists: move the old apps to the Trash (recoverable).
    static func trashOldApps() {
        let fm = FileManager.default
        guard PatchEngine.isPatched(PatchEngine.destination) else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path }
        for app in oldPatched + [oldCompanion] where fm.fileExists(atPath: app.path) && !running.contains(app.resolvingSymlinksInPath().path) {
            try? fm.trashItem(at: app, resultingItemURL: nil)
        }
    }
}
