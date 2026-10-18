import AppKit

enum IconPainter {
    static func render() -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.39, blue: 0.89, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.08, green: 0.76, blue: 0.80, alpha: 1))!
        gradient.draw(in: background, angle: 70)

        let route = NSBezierPath()
        route.move(to: NSPoint(x: 265, y: 288))
        route.curve(to: NSPoint(x: 750, y: 270), controlPoint1: NSPoint(x: 180, y: 150), controlPoint2: NSPoint(x: 755, y: 140))
        route.lineWidth = 32; route.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.55).setStroke(); route.stroke()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 246, y: 269, width: 38, height: 38)).fill()
        NSColor(calibratedRed: 1, green: 0.77, blue: 0.32, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 720, y: 240, width: 60, height: 60)).fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor(calibratedRed: 0.02, green: 0.22, blue: 0.50, alpha: 0.2)
        shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
        let pin = NSBezierPath()
        pin.move(to: NSPoint(x: 512, y: 320))
        pin.curve(to: NSPoint(x: 290, y: 616), controlPoint1: NSPoint(x: 460, y: 389), controlPoint2: NSPoint(x: 290, y: 492))
        pin.curve(to: NSPoint(x: 512, y: 836), controlPoint1: NSPoint(x: 290, y: 744), controlPoint2: NSPoint(x: 387, y: 836))
        pin.curve(to: NSPoint(x: 734, y: 616), controlPoint1: NSPoint(x: 637, y: 836), controlPoint2: NSPoint(x: 734, y: 744))
        pin.curve(to: NSPoint(x: 512, y: 320), controlPoint1: NSPoint(x: 734, y: 492), controlPoint2: NSPoint(x: 564, y: 389))
        pin.close()
        pin.append(NSBezierPath(ovalIn: NSRect(x: 421, y: 535, width: 182, height: 182)))
        pin.windingRule = .evenOdd
        NSColor.white.setFill(); pin.fill()
        NSGraphicsContext.restoreGraphicsState()
        image.unlockFocus()
        return image
    }

    static func writeIconSet(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = render()
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSGraphicsContext.current?.imageInterpolation = .high
                image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}
