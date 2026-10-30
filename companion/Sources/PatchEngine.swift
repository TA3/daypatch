// Builds "~/Applications/Patched Dia.app" from /Applications/Dia.app: a copy with
// daypatch.dylib injected, re-signed ad hoc. Same steps as build.sh, without
// needing a compiler: the dylib ships inside DayPatch.app.
import AppKit

enum PatchError: LocalizedError {
    case diaMissing, daypatchRunning, busy, step(String)
    var errorDescription: String? {
        switch self {
        case .diaMissing: return "Dia isn't installed in /Applications."
        case .daypatchRunning: return "Quit Patched Dia first."
        case .busy: return "Already patching."
        case .step(let s): return s
        }
    }
}

struct PatchStatus {
    enum State { case upToDate, needsPatch(String), notInstalled, diaMissing }
    var state: State
    var diaVersion: String?
    var patchedFrom: String?
}

extension PatchStatus {
    var isUpToDate: Bool { if case .upToDate = state { return true }; return false }
}

final class PatchEngine {
    static let source = URL(fileURLWithPath: "/Applications/Dia.app")
    static let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Patched Dia.app")

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

    func status() -> PatchStatus {
        guard let src = Self.info(Self.source) else { return PatchStatus(state: .diaMissing) }
        let diaBuild = src["CFBundleVersion"] as? String
        let diaVersion = Self.version(Self.source)
        guard let dst = Self.info(Self.destination) else {
            return PatchStatus(state: .notInstalled, diaVersion: diaVersion)
        }
        let patchedFrom = dst["DayPatchSourceBuild"] as? String
        var s = PatchStatus(state: .upToDate, diaVersion: diaVersion, patchedFrom: Self.version(Self.destination))
        if patchedFrom == nil {
            s.state = .needsPatch("Built outside DayPatch")
        } else if patchedFrom != diaBuild {
            s.state = .needsPatch("Dia was updated")
        } else if (dst["DayPatchPatchVersion"] as? String) != patchVersion {
            s.state = .needsPatch("New daypatch version")
        }
        return s
    }

    // Compare paths, not URLs: a running app's bundleURL has a trailing slash.
    private static func isRunning(_ app: URL) -> Bool {
        let path = app.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.resolvingSymlinksInPath().path == path }
    }

    static var patchedIsRunning: Bool { isRunning(destination) }
    static var diaIsRunning: Bool { isRunning(source) }

    /// Runs off the main thread; takes ~10 s (APFS clone + signing).
    func patch() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.source.path) else { throw PatchError.diaMissing }
        guard !Self.patchedIsRunning else { throw PatchError.daypatchRunning }
        let lockDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/daypatch")
        try? fm.createDirectory(at: lockDir, withIntermediateDirectories: true)
        let lock = open(lockDir.appendingPathComponent("patch.lock").path, O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { if lock >= 0 { close(lock) }; throw PatchError.busy }
        defer { flock(lock, LOCK_UN); close(lock) }

        let parent = Self.destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".Patched Dia.app.new")
        try? fm.removeItem(at: staging)

        // APFS clone: near-instant and takes no extra disk space until files change.
        try run("/bin/cp", ["-cR", Self.source.path, staging.path], "Copying Dia")
        let frameworks = staging.appendingPathComponent("Contents/Frameworks/daypatch.dylib")
        try fm.copyItem(at: dylib, to: frameworks)
        try run("/usr/bin/codesign", ["-f", "-s", "-", frameworks.path], "Signing the patch")

        // Load the patch from the binary itself (a weak load command), rather than via
        // DYLD_INSERT_LIBRARIES: Patched Dia then doesn't need to accept injected code
        // from the environment.
        let exe = staging.appendingPathComponent("Contents/MacOS/Dia")
        try run("/usr/bin/codesign", ["--remove-signature", exe.path], "Unsigning Dia's executable")
        try Self.insertLoadCommand(into: exe, dylib: "@executable_path/../Frameworks/daypatch.dylib")

        let plistURL = staging.appendingPathComponent("Contents/Info.plist")
        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else { throw PatchError.step("Reading Info.plist failed") }
        plist.removeValue(forKey: "LSEnvironment")
        plist["SUEnableAutomaticChecks"] = false   // updates come through the regular Dia
        plist["CFBundleName"] = "Patched Dia"
        plist["DayPatchSourceBuild"] = Self.info(Self.source)?["CFBundleVersion"]
        plist["DayPatchPatchVersion"] = patchVersion
        guard (plist as NSDictionary).write(to: plistURL, atomically: true) else { throw PatchError.step("Writing Info.plist failed") }

        try run("/usr/bin/codesign", ["-f", "-s", "-", "--options", "runtime", "--entitlements", entitlements.path, staging.path], "Signing Patched Dia")

        if fm.fileExists(atPath: Self.destination.path) { try fm.removeItem(at: Self.destination) }  // our own generated copy
        try fm.moveItem(at: staging, to: Self.destination)
        _ = try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                     ["-f", Self.destination.path], "Registering")
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
