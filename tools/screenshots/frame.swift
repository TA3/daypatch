// Dev tool: places rendered views on a styled background for the README.
//   swift tools/screenshots/frame.swift <raw-dir> <out-dir>
// Reads commandbar.png, settings.png, companion.png (2x); writes
// <out-dir>/commandbar.png and <out-dir>/apps.png (2x).
import AppKit

let raw = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

func load(_ name: String) -> NSImage {
    let img = NSImage(contentsOf: raw.appendingPathComponent(name))!
    let rep = img.representations[0]
    img.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)   // back to points
    return img
}

/// Fine monochrome grain, tiled over the backdrop.
let grain: NSImage = {
    let n = 256
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 2,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedWhite, bytesPerRow: 0, bitsPerPixel: 0)!
    var rng = SystemRandomNumberGenerator()
    let p = rep.bitmapData!
    for i in 0..<(n * n) {
        p[i * 2] = UInt8.random(in: 0...255, using: &rng)       // grey level
        p[i * 2 + 1] = UInt8.random(in: 10...26, using: &rng)   // low, varying opacity
    }
    let img = NSImage(size: NSSize(width: n / 2, height: n / 2))  // 2 px per point: grain stays fine at 2x
    img.addRepresentation(rep)
    return img
}()

/// Dia-coloured backdrop: warm near-black with yellow and amber glows, plus grain.
func drawBackground(_ r: NSRect) {
    NSGradient(colors: [rgb(0.08, 0.08, 0.08), rgb(0.10, 0.09, 0.08), rgb(0.06, 0.06, 0.06)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: r, angle: -35)
    // Glows are added like light (plus-lighter), so yellow stays yellow on black instead of turning olive.
    NSGraphicsContext.current?.compositingOperation = .plusLighter
    func glow(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ strength: CGFloat) {
        let p = NSPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        NSGradient(colors: [c.withAlphaComponent(strength), c.withAlphaComponent(strength * 0.35), c.withAlphaComponent(0)],
                   atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
            .draw(fromCenter: p, radius: 0, toCenter: p, radius: radius * max(r.width, r.height), options: [])
    }
    glow(rgb(1.00, 0.70, 0.02), 0.16, 1.02, 0.42, 0.95)   // Dia yellow, rising at the top left
    glow(rgb(1.00, 0.45, 0.05), 0.98, -0.02, 0.42, 0.75)  // amber, bottom right
    glow(rgb(1.00, 0.78, 0.20), 0.85, 1.05, 0.22, 0.35)   // pale sun, top right
    NSGraphicsContext.current?.compositingOperation = .sourceOver
    NSColor(patternImage: grain).setFill()
    NSGraphicsContext.current?.patternPhase = .zero
    r.fill(using: .sourceOver)
}

/// A floating card (or a window, with a title bar and traffic lights) with a soft shadow.
func drawCard(_ img: NSImage, at origin: NSPoint, titleBar: String?) -> NSRect {
    let bar: CGFloat = titleBar == nil ? 0 : 30
    let frame = NSRect(x: origin.x, y: origin.y, width: img.size.width, height: img.size.height + bar)
    let radius: CGFloat = titleBar == nil ? 16 : 12
    let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = rgb(0, 0, 0, 0.55); sh.shadowBlurRadius = 48; sh.shadowOffset = NSSize(width: 0, height: -22); sh.set()
    rgb(0.12, 0.12, 0.13).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); shape.addClip()
    img.draw(in: NSRect(x: frame.minX, y: frame.minY, width: img.size.width, height: img.size.height))
    if let title = titleBar {
        let barRect = NSRect(x: frame.minX, y: frame.maxY - bar, width: frame.width, height: bar)
        rgb(0.12, 0.12, 0.13).setFill(); barRect.fill()
        for (i, c) in [rgb(1.0, 0.37, 0.34), rgb(1.0, 0.74, 0.18), rgb(0.16, 0.79, 0.25)].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: barRect.minX + 14 + CGFloat(i) * 20, y: barRect.midY - 6, width: 12, height: 12)).fill()
        }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: rgb(1, 1, 1, 0.72)]
        let s = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(at: NSPoint(x: barRect.midX - s.width / 2, y: barRect.midY - s.height / 2), withAttributes: a)
    }
    NSGraphicsContext.restoreGraphicsState()
    rgb(1, 1, 1, 0.10).setStroke(); shape.lineWidth = 1; shape.stroke()
    return frame
}

func render(size: NSSize, to name: String, _ draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("wrote", out.appendingPathComponent(name).path)
}

// 1. Command bar, floating.
let bar = load("commandbar.png")
let barCanvas = NSSize(width: bar.size.width + 200, height: bar.size.height + 190)
render(size: barCanvas, to: "commandbar.png") { r in
    drawBackground(r)
    _ = drawCard(bar, at: NSPoint(x: (r.width - bar.size.width) / 2, y: (r.height - bar.size.height) / 2 + 8), titleBar: nil)
}

// 2. Settings pane and the DayPatch app, side by side.
let settings = load("settings.png"), app = load("companion.png")
let gap: CGFloat = 56, pad: CGFloat = 80
let appsCanvas = NSSize(width: pad * 2 + settings.size.width + gap + app.size.width,
                        height: pad * 2 + max(settings.size.height, app.size.height) + 30)
render(size: appsCanvas, to: "apps.png") { r in
    drawBackground(r)
    let top = r.maxY - pad
    _ = drawCard(settings, at: NSPoint(x: pad, y: top - settings.size.height - 30 - 40), titleBar: "Settings — DayPatch")
    _ = drawCard(app, at: NSPoint(x: pad + settings.size.width + gap, y: top - app.size.height - 30), titleBar: "DayPatch")
}
