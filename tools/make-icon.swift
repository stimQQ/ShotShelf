// Draws the app icon (a white viewfinder on a blue rounded square) and writes Resources/AppIcon.icns.
// Run from the repo root: swift tools/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024 // design on a 1024 grid

    // macOS icon grid: 824pt body centered on a 1024 canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.36, green: 0.66, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.12, green: 0.40, blue: 0.96, alpha: 1))!.draw(in: shape, angle: -90)

    // Viewfinder corners.
    NSColor.white.setStroke()
    let inset: CGFloat = 250 * s, arm: CGFloat = 130 * s
    let r = body.insetBy(dx: inset - 100 * s, dy: inset - 100 * s)
    let corners: [(NSPoint, CGFloat, CGFloat)] = [
        (NSPoint(x: r.minX, y: r.maxY), 1, -1), (NSPoint(x: r.maxX, y: r.maxY), -1, -1),
        (NSPoint(x: r.minX, y: r.minY), 1, 1), (NSPoint(x: r.maxX, y: r.minY), -1, 1),
    ]
    for (p, dx, dy) in corners {
        let path = NSBezierPath()
        path.lineWidth = 56 * s
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: p.x, y: p.y + dy * arm))
        path.line(to: p)
        path.line(to: NSPoint(x: p.x + dx * arm, y: p.y))
        path.stroke()
    }
    // Lens in the middle.
    NSColor.white.setFill()
    let lens: CGFloat = 150 * s
    NSBezierPath(ovalIn: NSRect(x: 512 * s - lens / 2, y: 512 * s - lens / 2, width: lens, height: lens)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! draw(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
