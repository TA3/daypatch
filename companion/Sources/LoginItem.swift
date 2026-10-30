// "Open at Login" via a per-user LaunchAgent (works for an ad-hoc signed app,
// unlike SMAppService which wants a Developer ID).
import Foundation

enum LoginItem {
    static let label = "dev.ta3.daypatch"
    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func set(_ on: Bool) {
        if on {
            let agent: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath, "--args", "--login"],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            (agent as NSDictionary).write(to: plist, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: plist)
        }
    }
}
