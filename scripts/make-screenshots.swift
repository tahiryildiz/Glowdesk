// Composes the README images from panel snapshots rendered with demo data.
// Usage:
//   swift build && .build/debug/Glowdesk --snapshot /tmp/glowdesk-shots
//   swift scripts/make-screenshots.swift /tmp/glowdesk-shots/en docs
import AppKit

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "docs")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func panel(_ name: String) -> NSImage { NSImage(contentsOf: source.appendingPathComponent("\(name).png"))! }
func pixelSize(_ image: NSImage) -> NSSize {
    let rep = image.representations.first!
    return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}
func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

/// Draws into a bitmap where one point is one pixel; y grows upward (AppKit).
func render(_ size: NSSize, to name: String, _ draw: (NSRect) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    print("Wrote \(output.path)/\(name)")
}

/// A dark room lit by a few Hue lights.
func room(_ rect: NSRect, glows: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: UInt32, alpha: CGFloat)]) {
    hex(0x100E0D).setFill(); rect.fill()
    let ctx = NSGraphicsContext.current!.cgContext
    for glow in glows {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [hex(glow.color, glow.alpha).cgColor, hex(glow.color, 0).cgColor] as CFArray, locations: [0, 1])!
        let center = CGPoint(x: rect.width * glow.x, y: rect.height * glow.y)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: glow.radius, options: [])
    }
}

/// The panel as it appears on screen: rounded, outlined, floating, with the arrow toward the menu bar.
func drawPanel(_ image: NSImage, at origin: NSPoint, arrowX: CGFloat? = nil) {
    let size = pixelSize(image)
    let frame = NSRect(origin: origin, size: size)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 36, yRadius: 36)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = 90; shadow.shadowOffset = NSSize(width: 0, height: -40)
    shadow.set()
    hex(0x1A1917).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    image.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
    if let arrowX {
        let arrow = NSBezierPath()
        let top = frame.maxY + 22
        arrow.move(to: NSPoint(x: arrowX - 22, y: frame.maxY))
        arrow.curve(to: NSPoint(x: arrowX, y: top), controlPoint1: NSPoint(x: arrowX - 10, y: frame.maxY + 4), controlPoint2: NSPoint(x: arrowX - 6, y: top))
        arrow.curve(to: NSPoint(x: arrowX + 22, y: frame.maxY), controlPoint1: NSPoint(x: arrowX + 6, y: top), controlPoint2: NSPoint(x: arrowX + 10, y: frame.maxY + 4))
        arrow.close()
        hex(0x1A1917).setFill(); arrow.fill()
    }
    hex(0xFFFFFF, 0.1).setStroke(); shape.lineWidth = 1.5; shape.stroke()
}

func symbol(_ name: String, _ color: NSColor, size: CGFloat) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [color])))!
}

func text(_ string: String, font: NSFont, color: NSColor, in rect: NSRect, lineHeight: CGFloat? = nil, kern: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    if let lineHeight { paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight }
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern])
        .draw(with: rect, options: [.usesLineFragmentOrigin])
}

// Hero: the menu bar, the yellow bulb, and the Rooms panel hanging from it.
let rooms = panel("1-rooms")
let heroSize = NSSize(width: 2400, height: 1440)
try render(heroSize, to: "hero.png") { rect in
    room(rect, glows: [(0.12, 0.08, 1000, 0xF0832E, 0.38), (0.55, 0.3, 900, 0xC2449E, 0.30), (0.95, 0.95, 1100, 0x4B3BD6, 0.32)])
    // Menu bar.
    let bar = NSRect(x: 0, y: rect.height - 56, width: rect.width, height: 56)
    hex(0x2A2724, 0.72).setFill(); bar.fill()
    let clock = NSAttributedString(string: "Tue 9:41", attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .medium), .foregroundColor: NSColor.white])
    clock.draw(at: NSPoint(x: rect.width - 48 - clock.size().width, y: bar.minY + 13))
    var x = rect.width - 48 - clock.size().width - 70
    for name in ["switch.2", "magnifyingglass", "battery.100percent", "wifi"] {
        let icon = symbol(name, .white, size: 24)
        icon.draw(at: NSPoint(x: x - icon.size.width / 2, y: bar.minY + (56 - icon.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
        x -= 66
    }
    let bulbX = x
    let bulb = symbol("lightbulb.fill", hex(0xFFC71A), size: 26)
    bulb.draw(at: NSPoint(x: bulbX - bulb.size.width / 2, y: bar.minY + (56 - bulb.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
    // Panel below the bulb.
    let size = pixelSize(rooms)
    let panelOrigin = NSPoint(x: bulbX - size.width / 2, y: bar.minY - 22 - size.height)
    drawPanel(rooms, at: panelOrigin, arrowX: bulbX)
    // Headline.
    let left: CGFloat = 170
    text("Your Hue lights,\nin the menu bar.", font: NSFont.systemFont(ofSize: 112, weight: .heavy, width: .expanded),
         color: hex(0xF2EEE6), in: NSRect(x: left, y: 560, width: 1280, height: 300), lineHeight: 126, kern: -2.5)
    text("Every room is a fader that glows in the color of its lights.\nDrag to dim, tap to switch, scroll over the bulb to set the mood.",
         font: NSFont.systemFont(ofSize: 38, weight: .regular), color: hex(0xB4ADA3),
         in: NSRect(x: left, y: 400, width: 1250, height: 120), lineHeight: 54)
}

// Tour: Lights on the left, Scenes over History on the right.
let lights = panel("2-lights"), scenes = panel("3-scenes"), history = panel("5-history")
let pad: CGFloat = 120, gap: CGFloat = 64
let rightHeight = pixelSize(scenes).height + gap + pixelSize(history).height
let tourHeight = pad * 2 + max(pixelSize(lights).height, rightHeight)
let tourSize = NSSize(width: pad * 2 + 720 * 2 + gap, height: tourHeight)
try render(tourSize, to: "tour.png") { rect in
    room(rect, glows: [(0.15, 0.85, 900, 0x4B3BD6, 0.32), (0.85, 0.6, 900, 0xC2449E, 0.26), (0.5, 0.05, 900, 0xF0832E, 0.30)])
    let top = rect.height - pad
    drawPanel(lights, at: NSPoint(x: pad, y: top - pixelSize(lights).height))
    drawPanel(scenes, at: NSPoint(x: pad + 720 + gap, y: top - pixelSize(scenes).height))
    drawPanel(history, at: NSPoint(x: pad + 720 + gap, y: top - pixelSize(scenes).height - gap - pixelSize(history).height))
}
