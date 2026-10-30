// Dev tool: renders the DayPatch window for the README (dark mode, 2x).
// Uses this Mac's real status; shows a demo feature list if there's no health report yet.
//   swiftc -O -module-name DayPatch -target arm64-apple-macos14 -o build/shots-companion \
//     $(ls companion/Sources/*.swift | grep -v /main.swift) tools/screenshots/companion.swift
//   (run it from inside a .app's Contents/MacOS so Bundle.main finds VERSION)
import AppKit
import SwiftUI

@main struct Shot {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let fm = FileManager.default
        var wroteDemo = false
        if !fm.fileExists(atPath: Health.url.path) {
            try? fm.createDirectory(at: Health.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let names = ["Command bar", "Dia editor anchoring", "Hide AI features", "New tab without a tab", "On-device AI off",
                         "Settings pane", "Sidebar URL bar", "URL bar hiding", "Web engine blocking"]
            let demo: [String: Any] = ["patchVersion": "demo", "diaVersion": "1.55.1", "diaBuild": "89833", "date": "demo",
                                       "checks": Dictionary(uniqueKeysWithValues: names.map { ($0, true) })]
            try? JSONSerialization.data(withJSONObject: demo).write(to: Health.url)
            wroteDemo = true
        }
        defer { if wroteDemo { try? fm.removeItem(at: Health.url) } }
        let c = Controller()
        let host = NSHostingView(rootView: DayPatchWindowView(c: c).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSApp.appearance
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 900)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let size = host.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("wrote", CommandLine.arguments[1], size)
    }
}
