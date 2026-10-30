// DayPatch's icons, drawn in code.
//  - App icon: two sticking plasters on a tile in Dia's black (original artwork;
//    it doesn't use or imitate Dia's logo, just its background colour).
//  - Menu bar: a plaster silhouette (template image).
import AppKit

enum DayPatchIcon {
    enum Badge { case none, busy, attention }

    /// The mark in `rect` (unit square scaled), stroked/filled with the current color.
    static func drawMark(in rect: NSRect, lineWidth: CGFloat) {
        let s = min(rect.width, rect.height)
        let c = NSPoint(x: rect.midX, y: rect.midY - s * 0.06)
        let r = s * 0.34
        let arc = NSBezierPath()
        // An open arc, wider than a semicircle, like a rainbow over the horizon.
        arc.appendArc(withCenter: c, radius: r, startAngle: 200, endAngle: -20, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        arc.stroke()
        let d = s * 0.17
        NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2 - s * 0.02, width: d, height: d)).fill()
    }

    /// 18 pt template image for the menu bar.
    static func menuBarImage(_ badge: Badge) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            drawPlasterGlyph(in: rect)
            switch badge {
            case .none: break
            case .busy:
                // Three small dots under the mark: working.
                for i in 0..<3 { NSBezierPath(ovalIn: NSRect(x: 5.5 + CGFloat(i) * 2.8, y: 0.5, width: 1.6, height: 1.6)).fill() }
            case .attention:
                // A knocked-out circle with "!" at the bottom right.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 10, y: 0, width: 8.5, height: 8.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: 11, y: 1, width: 6.5, height: 6.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(rect: NSRect(x: 13.85, y: 3.6, width: 0.8, height: 2.6)).fill()
                NSBezierPath(rect: NSRect(x: 13.85, y: 2.3, width: 0.8, height: 0.8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    /// One-colour plaster: body filled, gauze pad and breathing holes knocked out.
    static func drawPlasterGlyph(in rect: NSRect) {
        let s = rect.width
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: rect.midX, yBy: rect.midY + s * 0.03); t.rotate(byDegrees: -40); t.concat()
        let length = s * 0.98, width = s * 0.42
        NSBezierPath(roundedRect: NSRect(x: -length / 2, y: -width / 2, width: length, height: width), xRadius: width / 2, yRadius: width / 2).fill()
        NSGraphicsContext.current?.compositingOperation = .clear
        let pad = NSRect(x: -length * 0.14, y: -width * 0.3, width: length * 0.28, height: width * 0.6)
        let padPath = NSBezierPath(roundedRect: pad, xRadius: width * 0.12, yRadius: width * 0.12)
        padPath.lineWidth = max(1, s * 0.06); padPath.stroke()
        let hole = s * 0.07
        for side in [-1.0, 1.0] as [CGFloat] {
            for row in [-0.5, 0.5] as [CGFloat] {
                let x = side * length * 0.3, y = row * width * 0.36
                NSBezierPath(ovalIn: NSRect(x: x - hole / 2, y: y - hole / 2, width: hole, height: hole)).fill()
            }
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A full-colour sticking plaster centred at `c`.
    static func drawPlaster(center c: NSPoint, length: CGFloat, width: CGFloat, angle: CGFloat) {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: c.x, yBy: c.y); t.rotate(byDegrees: angle); t.concat()
        let body = NSRect(x: -length / 2, y: -width / 2, width: length, height: width)
        let shape = NSBezierPath(roundedRect: body, xRadius: width / 2, yRadius: width / 2)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = rgb(0, 0, 0, 0.35); sh.shadowBlurRadius = width * 0.18; sh.shadowOffset = NSSize(width: 0, height: -width * 0.06); sh.set()
        rgb(0.93, 0.74, 0.56).setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        NSGradient(colors: [rgb(0.97, 0.82, 0.66), rgb(0.91, 0.70, 0.52)])!.draw(in: body, angle: -90)
        rgb(0.78, 0.55, 0.38, 0.55).setFill()
        let hole = width * 0.07
        for side in [-1.0, 1.0] as [CGFloat] {
            for col in 0..<3 { for row in 0..<3 {
                let x = side * (length * 0.20 + CGFloat(col) * width * 0.24), y = (CGFloat(row) - 1) * width * 0.24
                NSBezierPath(ovalIn: NSRect(x: x - hole / 2, y: y - hole / 2, width: hole, height: hole)).fill()
            } }
        }
        let pad = NSRect(x: -length * 0.14, y: -width * 0.36, width: length * 0.28, height: width * 0.72)
        let padPath = NSBezierPath(roundedRect: pad, xRadius: width * 0.1, yRadius: width * 0.1)
        NSGradient(colors: [rgb(1.0, 0.95, 0.88), rgb(0.96, 0.88, 0.78)])!.draw(in: padPath, angle: -90)
        rgb(0.85, 0.70, 0.55, 0.6).setStroke(); padPath.lineWidth = width * 0.025; padPath.stroke()
        rgb(1, 1, 1, 0.35).setStroke()
        let edge = NSBezierPath(roundedRect: body.insetBy(dx: width * 0.03, dy: width * 0.03), xRadius: width / 2, yRadius: width / 2)
        edge.lineWidth = width * 0.03; edge.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Full-colour app icon at `size` px: two plasters on a tile in Dia's black.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            drawBlackTile(in: r)
            // Variant C: a big plaster, and a smaller one across it, slightly off-centre.
            drawPlaster(center: NSPoint(x: r.midX + size * 0.04, y: r.midY + size * 0.05), length: size * 0.86, width: size * 0.33, angle: -32)
            drawPlaster(center: NSPoint(x: r.midX - size * 0.06, y: r.midY - size * 0.12), length: size * 0.62, width: size * 0.24, angle: 18)
            return true
        }
    }

    /// Dark rounded tile in Dia's black (the same near-black gradient as Dia's icon).
    static func drawBlackTile(in r: NSRect) {
        let s = r.width
        let tileRect = NSRect(x: r.minX + s * 0.098, y: r.minY + s * 0.098, width: s * 0.804, height: s * 0.804)
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: s * 0.18, yRadius: s * 0.18)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.3); sh.shadowBlurRadius = s * 0.02; sh.shadowOffset = NSSize(width: 0, height: -s * 0.008); sh.set()
        NSColor.black.setFill(); tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); tile.addClip()
        NSGradient(starting: NSColor(white: 0.15, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!.draw(in: tileRect, angle: -90)
        // Soft top highlight, like macOS icons.
        NSGradient(starting: NSColor.white.withAlphaComponent(0.06), ending: .clear)!
            .draw(in: NSRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The original arc-over-dot icon (kept for reference).
    static func arcIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = size * 0.1, box = rect.insetBy(dx: inset, dy: inset)
            let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = size * 0.025
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
            shadow.set()
            NSColor.black.setFill(); shape.fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            NSGraphicsContext.current?.saveGraphicsState()
            shape.addClip()
            NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.45, blue: 0.48, alpha: 1),
                                NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1),
                                NSColor(srgbRed: 0.20, green: 0.24, blue: 0.62, alpha: 1)],
                       atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: box, angle: -70)
            // Soft highlight across the top.
            NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
                .draw(in: NSRect(x: box.minX, y: box.midY, width: box.width, height: box.height / 2), angle: -90)
            NSColor.white.set()
            drawMark(in: box.insetBy(dx: box.width * 0.2, dy: box.width * 0.2), lineWidth: box.width * 0.075)
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
    }

    /// Writes AppIcon.icns into `dir` (build step: `DayPatch --make-icon <dir>`).
    static func writeICNS(to dir: URL) throws {
        let set = dir.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: set)
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                appIcon(size: px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
                try rep.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
            }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", set.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
        try p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(at: set)
    }
}
