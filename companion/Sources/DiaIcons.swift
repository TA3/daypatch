// Dia's app-icon choices: the .icns pack shipped inside DayPatch.app and copied
// into Dia at patch time. The selection is shared with the running dylib.
import AppKit

struct DiaIconChoice: Identifiable {
    let id: String
    let name: String
    let image: NSImage?
}

enum DiaIcons {
    static let changed = Notification.Name("dev.ta3.daypatch.appIconChanged")

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/daypatch")
    }
    static var storeURL: URL { supportDir.appendingPathComponent("app-icon.id") }

    static let choices: [DiaIconChoice] = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Icons"),
              let data = try? Data(contentsOf: dir.appendingPathComponent("icons.json")),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String,
                  let file = item["file"] as? String else { return nil }
            let url = dir.appendingPathComponent(file)
            guard let image = NSImage(contentsOf: url) else { return nil }
            return DiaIconChoice(id: id, name: name, image: image)
        }
    }()

    static var defaultImage: NSImage? {
        let app = PatchEngine.destination
        if FileManager.default.fileExists(atPath: app.path) {
            let image = NSWorkspace.shared.icon(forFile: app.path)
            image.size = NSSize(width: 40, height: 40)
            return image
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
    }

    static func currentID() -> String? {
        guard let value = try? String(contentsOf: storeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return choices.contains { $0.id == value } ? value : nil
    }

    static func select(_ id: String?) {
        if let id, !choices.contains(where: { $0.id == id }) { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        if let id {
            try? id.write(to: storeURL, atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(at: storeURL)
        }
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
