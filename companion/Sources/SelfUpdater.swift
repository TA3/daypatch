// Updates DayPatch itself from the project's GitHub Releases.
//
// Each release carries DayPatch.zip and DayPatch.zip.sig, an ed25519 signature made in
// CI with a key that only exists as a GitHub secret. DayPatch installs an update only
// if the signature matches the public key built into it (Info.plist
// DayPatchUpdatePublicKey), so a tampered release or download is rejected.
import AppKit
import CryptoKit

struct DayPatchRelease {
    let version: String
    let zip: URL
    let signature: URL
    let notesURL: URL?
}

enum SelfUpdateError: LocalizedError {
    case noKey, feed(String), verify(String), install(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "This build of DayPatch can't verify updates (no update key)."
        case .feed(let s): return "Couldn't check for DayPatch updates: \(s)"
        case .verify(let s): return "DayPatch update didn't verify: \(s)"
        case .install(let s): return "Couldn't install the DayPatch update: \(s)"
        }
    }
}

enum SelfUpdater {
    static var repo: String { Bundle.main.object(forInfoDictionaryKey: "DayPatchRepo") as? String ?? "TA3/daypatch" }
    static var publicKey: String? {
        (Bundle.main.object(forInfoDictionaryKey: "DayPatchUpdatePublicKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// "1.10.0" > "1.9.2"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The latest release if it's newer than this build, else nil.
    static func latest() async throws -> DayPatchRelease? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("DayPatch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }   // no releases yet
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SelfUpdateError.feed("HTTP \(code)") }
        guard (j["draft"] as? Bool) != true, (j["prerelease"] as? Bool) != true,
              let tag = j["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: currentVersion) else { return nil }
        let assets = (j["assets"] as? [[String: Any]]) ?? []
        func asset(_ name: String) -> URL? {
            (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String).flatMap(URL.init(string:))
        }
        guard let zip = asset("DayPatch.zip"), let sig = asset("DayPatch.zip.sig") else { throw SelfUpdateError.feed("release \(tag) has no signed DayPatch.zip") }
        return DayPatchRelease(version: version, zip: zip, signature: sig, notesURL: (j["html_url"] as? String).flatMap(URL.init(string:)))
    }

    /// Downloads, verifies and swaps in the new DayPatch.app. The caller relaunches.
    static func install(_ r: DayPatchRelease) async throws {
        guard let keyB64 = publicKey, let keyData = Data(base64Encoded: keyB64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw SelfUpdateError.noKey }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("daypatch-update-\(r.version)")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zip = try await download(r.zip, to: work.appendingPathComponent("DayPatch.zip"))
        let sigText = try String(contentsOf: try await download(r.signature, to: work.appendingPathComponent("DayPatch.zip.sig")), encoding: .utf8)
        guard let sig = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(sig, for: try Data(contentsOf: zip, options: .mappedIfSafe)) else {
            throw SelfUpdateError.verify("signature doesn't match")
        }

        let unpack = work.appendingPathComponent("unpacked")
        try PatchEngine(resources: Bundle.main.resourceURL!).run("/usr/bin/ditto", ["-x", "-k", zip.path, unpack.path], "Unzipping")
        let app = unpack.appendingPathComponent("DayPatch.app")
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == r.version else {
            throw SelfUpdateError.verify("unexpected app in the archive")
        }

        // Swap: the running copy goes to the Trash (recoverable), the new one takes its place.
        let current = Bundle.main.bundleURL
        do {
            try fm.trashItem(at: current, resultingItemURL: nil)
            try fm.moveItem(at: app, to: current)
        } catch {
            throw SelfUpdateError.install(error.localizedDescription)
        }
    }

    /// Starts the newly installed DayPatch after this process exits.
    static func relaunch(arguments: [String] = []) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        let args = arguments.isEmpty ? "" : " --args " + arguments.joined(separator: " ")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(Bundle.main.bundlePath)\"\(args)"]
        try? p.run()
    }

    private static func download(_ url: URL, to dest: URL) async throws -> URL {
        var req = URLRequest(url: url)
        req.setValue("DayPatch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw SelfUpdateError.install("download failed") }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}
