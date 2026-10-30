// Patches Dia with daypatch.dylib (shipped inside DayPatch.app, so no compiler is needed).
//
// Two modes:
//  - In place (default): /Applications/Dia.app itself becomes "Dia ✦". An untouched
//    copy of the original is kept as a backup (an APFS clone, so it takes no space),
//    Dia's own updater stays on, and after it installs an update DayPatch re-patches.
//  - Copy: a separate ~/Applications/Dia ✦.app; the regular Dia stays stock.
import AppKit

enum PatchMode: String { case inPlace, copy }

enum PatchError: LocalizedError {
    case diaMissing, patchedRunning, busy, noBackup, permission, step(String)
    var errorDescription: String? {
        switch self {
        case .diaMissing: return "Dia isn't installed in /Applications."
        case .patchedRunning: return "Quit Dia first."
        case .busy: return "Already patching."
        case .noBackup: return "The original Dia backup is missing. Reinstall Dia, then patch again."
        case .permission: return "macOS blocked DayPatch from changing Dia. Allow DayPatch in System Settings › Privacy & Security › App Management, then try again."
        case .step(let s): return s
        }
    }
}

struct PatchStatus {
    enum State { case upToDate, needsPatch(String), notInstalled, diaMissing, restored }
    var state: State
    var diaVersion: String?
    var patchedFrom: String?
}

extension PatchStatus {
    var isUpToDate: Bool { if case .upToDate = state { return true }; return false }
}

final class PatchEngine {
    /// The installed Dia. DAYPATCH_DIA_PATH points it elsewhere for testing.
    static var source: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["DAYPATCH_DIA_PATH"] ?? "/Applications/Dia.app")
    }
    static var supportDir: URL {
        ProcessInfo.processInfo.environment["DAYPATCH_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/daypatch")
    }
    /// The untouched original Dia, kept while Dia itself is patched.
    static var backup: URL { supportDir.appendingPathComponent("Dia-original.app") }
    static var copyDestination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Dia ✦.app")
    }
    static let appName = "Dia ✦"
    /// What to quit before patching: Dia itself in place, the copy otherwise.
    static var targetName: String { mode == .inPlace ? "Dia" : appName }

    static var mode: PatchMode {
        PatchMode(rawValue: UserDefaults.standard.string(forKey: "patchMode") ?? "") ?? .inPlace
    }
    /// The app the user runs: Dia itself (in place) or the copy.
    static var destination: URL { mode == .inPlace ? source : copyDestination }

    let dylib: URL
    let entitlements: URL
    let patchVersion: String

    init(resources: URL) {
        dylib = resources.appendingPathComponent("daypatch.dylib")
        entitlements = resources.appendingPathComponent("entitlements.plist")
        patchVersion = (try? String(contentsOf: resources.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    static func info(_ app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    static func version(_ app: URL) -> String? {
        guard let i = info(app) else { return nil }
        return "\(i["CFBundleShortVersionString"] ?? "?") (\(i["CFBundleVersion"] ?? "?"))"
    }

    static func isPatched(_ app: URL) -> Bool { info(app)?["DayPatchPatchVersion"] != nil }

    /// Set when the user chose Restore Original Dia: don't re-patch until they ask.
    static var restoredByUser: Bool {
        get { UserDefaults.standard.bool(forKey: "restoredByUser") }
        set { UserDefaults.standard.set(newValue, forKey: "restoredByUser") }
    }

    func status() -> PatchStatus {
        guard let src = Self.info(Self.source) else { return PatchStatus(state: .diaMissing) }
        if Self.mode == .inPlace {
            if !Self.isPatched(Self.source) {
                // Stock Dia: never patched, restored by the user, or just updated by Dia's own updater.
                let v = Self.version(Self.source)
                if Self.restoredByUser { return PatchStatus(state: .restored, diaVersion: v) }
                guard let b = Self.info(Self.backup) else { return PatchStatus(state: .notInstalled, diaVersion: v) }
                let updated = (b["CFBundleVersion"] as? String) != (src["CFBundleVersion"] as? String)
                return PatchStatus(state: .needsPatch(updated ? "Dia was updated" : "Dia isn't patched"), diaVersion: v)
            }
            var s = PatchStatus(state: .upToDate, diaVersion: Self.version(Self.backup) ?? Self.version(Self.source), patchedFrom: Self.version(Self.source))
            if (src["DayPatchPatchVersion"] as? String) != patchVersion { s.state = .needsPatch("New DayPatch version") }
            else if !FileManager.default.fileExists(atPath: Self.backup.path) { s.state = .needsPatch("Original backup missing") }
            return s
        }
        let diaBuild = src["CFBundleVersion"] as? String
        let diaVersion = Self.version(Self.source)
        guard let dst = Self.info(Self.copyDestination) else {
            return PatchStatus(state: .notInstalled, diaVersion: diaVersion)
        }
        let patchedFrom = dst["DayPatchSourceBuild"] as? String
        var s = PatchStatus(state: .upToDate, diaVersion: diaVersion, patchedFrom: Self.version(Self.copyDestination))
        if patchedFrom == nil {
            s.state = .needsPatch("Built outside DayPatch")
        } else if patchedFrom != diaBuild {
            s.state = .needsPatch("Dia was updated")
        } else if (dst["DayPatchPatchVersion"] as? String) != patchVersion {
            s.state = .needsPatch("New DayPatch version")
        }
        return s
    }

    // Compare paths, not URLs: a running app's bundleURL has a trailing slash.
    static func isRunning(_ app: URL) -> Bool {
        let path = app.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.resolvingSymlinksInPath().path == path }
    }

    /// Is the app DayPatch would replace running? (Dia itself in place; the copy otherwise.)
    static var patchedIsRunning: Bool { isRunning(destination) }
    static var diaIsRunning: Bool { isRunning(source) }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let lock = open(Self.supportDir.appendingPathComponent("patch.lock").path, O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { if lock >= 0 { close(lock) }; throw PatchError.busy }
        defer { flock(lock, LOCK_UN); close(lock) }
        return try body()
    }

    /// Runs off the main thread; takes ~10 s (APFS clone + signing).
    func patch() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.source.path) else { throw PatchError.diaMissing }
        guard !Self.patchedIsRunning else { throw PatchError.patchedRunning }
        Migration.mergeSplitProfiles()
        try withLock {
            let inPlace = Self.mode == .inPlace
            let pristine: URL
            if inPlace {
                // A stock Dia (first patch, or freshly updated by Dia) becomes the new backup.
                if !Self.isPatched(Self.source) {
                    try fm.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
                    let fresh = Self.supportDir.appendingPathComponent(".Dia-original.app.new")
                    try? fm.removeItem(at: fresh)
                    try run("/bin/cp", ["-cR", Self.source.path, fresh.path], "Backing up the original Dia")
                    try? fm.removeItem(at: Self.backup)
                    try fm.moveItem(at: fresh, to: Self.backup)
                }
                guard fm.fileExists(atPath: Self.backup.path) else { throw PatchError.noBackup }
                pristine = Self.backup
            } else {
                pristine = Self.source
            }

            let target = Self.destination
            let parent = target.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let staging = parent.appendingPathComponent(".\(target.lastPathComponent).daypatch-new")
            try? fm.removeItem(at: staging)

            // APFS clone: near-instant and takes no extra disk space until files change.
            try run("/bin/cp", ["-cR", pristine.path, staging.path], "Copying Dia")
            let frameworks = staging.appendingPathComponent("Contents/Frameworks/daypatch.dylib")
            try fm.copyItem(at: dylib, to: frameworks)
            try run("/usr/bin/codesign", ["-f", "-s", "-", frameworks.path], "Signing the patch")

            // Load the patch from the binary itself (a weak load command), rather than via
            // DYLD_INSERT_LIBRARIES: Dia ✦ then doesn't accept injected code from the environment.
            let exe = staging.appendingPathComponent("Contents/MacOS/Dia")
            try run("/usr/bin/codesign", ["--remove-signature", exe.path], "Unsigning Dia's executable")
            try Self.insertLoadCommand(into: exe, dylib: "@executable_path/../Frameworks/daypatch.dylib")

            let plistURL = staging.appendingPathComponent("Contents/Info.plist")
            guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else { throw PatchError.step("Reading Info.plist failed") }
            plist.removeValue(forKey: "LSEnvironment")
            if inPlace {
                plist.removeValue(forKey: "SUEnableAutomaticChecks")   // Dia's own updater keeps working
            } else {
                plist["SUEnableAutomaticChecks"] = false                // the copy follows the regular Dia
            }
            // Only the display name changes: Dia names its profile folder after CFBundleName,
            // so keeping "Dia" there keeps Dia ✦ on the same profile as the regular Dia.
            plist["CFBundleDisplayName"] = Self.appName
            plist["DayPatchSourceBuild"] = Self.info(pristine)?["CFBundleVersion"]
            plist["DayPatchPatchVersion"] = patchVersion
            guard (plist as NSDictionary).write(to: plistURL, atomically: true) else { throw PatchError.step("Writing Info.plist failed") }

            try run("/usr/bin/codesign", ["-f", "-s", "-", "--options", "runtime", "--entitlements", entitlements.path, staging.path], "Signing Dia ✦")
            try Self.swapIn(staging, at: target)
            Self.restoredByUser = false
        }
    }

    /// Puts the untouched original Dia back (in place mode). DayPatch then leaves it
    /// alone until the user patches again.
    func restoreOriginal() throws {
        let fm = FileManager.default
        guard Self.mode == .inPlace else { return }
        guard !Self.diaIsRunning else { throw PatchError.patchedRunning }
        guard fm.fileExists(atPath: Self.backup.path) else { throw PatchError.noBackup }
        try withLock {
            if !Self.isPatched(Self.source) { return }   // already stock
            let staging = Self.source.deletingLastPathComponent().appendingPathComponent(".Dia.app.daypatch-restore")
            try? fm.removeItem(at: staging)
            try run("/bin/cp", ["-cR", Self.backup.path, staging.path], "Restoring the original Dia")
            try Self.swapIn(staging, at: Self.source)
            Self.restoredByUser = true
        }
    }

    /// In place → copy: put the original Dia back, then build the copy.
    /// Copy → in place: patch Dia itself, then trash the copy.
    func switchMode(to mode: PatchMode) throws {
        guard mode != Self.mode else { return }
        guard !Self.diaIsRunning, !Self.isRunning(Self.copyDestination) else { throw PatchError.patchedRunning }
        if mode == .copy {
            try restoreOriginal()
            UserDefaults.standard.set(mode.rawValue, forKey: "patchMode")
            try patch()
            try? FileManager.default.removeItem(at: Self.backup)
        } else {
            UserDefaults.standard.set(mode.rawValue, forKey: "patchMode")
            do { try patch() } catch {
                UserDefaults.standard.set(PatchMode.copy.rawValue, forKey: "patchMode")
                throw error
            }
            try? FileManager.default.trashItem(at: Self.copyDestination, resultingItemURL: nil)
        }
    }

    /// Replaces `target` with `staging` (same folder): old one aside, new one in, old one removed.
    private static func swapIn(_ staging: URL, at target: URL) throws {
        let fm = FileManager.default
        let old = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).daypatch-old")
        try? fm.removeItem(at: old)
        do {
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: old) }
            try fm.moveItem(at: staging, to: target)
        } catch let e as NSError where e.domain == NSCocoaErrorDomain && (e.code == NSFileWriteNoPermissionError || e.code == 513) {
            if !fm.fileExists(atPath: target.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: target) }
            throw PatchError.permission
        }
        if (try? fm.removeItem(at: old)) == nil { try? fm.trashItem(at: old, resultingItemURL: nil) }
        _ = try? PatchEngine.runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                                     ["-f", target.path])
    }

    static func runTool(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return out
    }

    /// Adds LC_LOAD_WEAK_DYLIB to a thin, unsigned 64-bit Mach-O (same as tools/insert-dylib.c).
    /// Weak, so the app still launches (unpatched) if the dylib is ever missing.
    static func insertLoadCommand(into exe: URL, dylib path: String) throws {
        var data = try Data(contentsOf: exe)
        func u32(_ o: Int) -> UInt32 { data.subdata(in: o..<o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func put(_ v: UInt32, _ o: Int) { withUnsafeBytes(of: v.littleEndian) { data.replaceSubrange(o..<o + 4, with: $0) } }
        guard u32(0) == 0xfeedfacf else { throw PatchError.step("Dia's executable isn't a thin 64-bit Mach-O") }
        let ncmds = Int(u32(16)), sizeofcmds = Int(u32(20)), headerSize = 32
        var off = headerSize, firstData = Int.max
        for _ in 0..<ncmds {
            let cmd = u32(off), size = Int(u32(off + 4))
            if cmd == 0x1d { throw PatchError.step("Dia's executable is still signed") }        // LC_CODE_SIGNATURE
            if cmd == 0xc || cmd == 0x80000018 {                                                  // LC_LOAD(_WEAK)_DYLIB
                let nameOff = Int(u32(off + 8))
                let name = data.subdata(in: off + nameOff..<off + size).split(separator: 0).first.map { String(decoding: $0, as: UTF8.self) }
                if name == path { return }
            }
            if cmd == 0x19 {                                                                      // LC_SEGMENT_64: find the first section data
                let nsects = Int(u32(off + 64))
                for i in 0..<nsects {
                    let sec = off + 72 + i * 80, secOff = Int(u32(sec + 48))
                    if secOff > 0 { firstData = min(firstData, secOff) }
                }
            }
            off += size
        }
        let bytes = Array(path.utf8) + [0]
        let size = (24 + bytes.count + 7) & ~7
        let end = headerSize + sizeofcmds
        guard end + size <= firstData else { throw PatchError.step("No room in Dia's header for the patch") }
        var cmd = Data(count: size)
        func cput(_ v: UInt32, _ o: Int) { withUnsafeBytes(of: v.littleEndian) { cmd.replaceSubrange(o..<o + 4, with: $0) } }
        cput(0x80000018, 0); cput(UInt32(size), 4); cput(24, 8); cput(2, 12); cput(0x10000, 16); cput(0x10000, 20)
        cmd.replaceSubrange(24..<24 + bytes.count, with: bytes)
        data.replaceSubrange(end..<end + size, with: cmd)
        put(UInt32(ncmds + 1), 16)
        put(UInt32(sizeofcmds + size), 20)
        try data.write(to: exe)
    }

    @discardableResult
    func run(_ tool: String, _ args: [String], _ what: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw PatchError.step("\(what) failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return out
    }
}
