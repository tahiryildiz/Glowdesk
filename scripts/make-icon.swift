// Draws the HueMenubar app icon: three light-desk faders on a warm graphite tile.
// Usage: swift scripts/make-icon.swift <output-dir>
// Writes AppIcon-1024.png and AppIcon.icns (via iconutil) into <output-dir>.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: an 824 pt tile centered on the 1024 canvas, with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x1A1917)); ctx.fillPath()
    ctx.restoreGState()

    // Console body: warm graphite with a little light from above.
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let body = CGGradient(colorsSpace: space, colors: [color(0x34302B), color(0x1C1A18)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(body, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Three faders, each filled with its light's color.
    let faders: [(level: CGFloat, top: UInt32, bottom: UInt32)] = [
        (0.62, 0xFFB648, 0xF0832E),   // warm white
        (0.88, 0xFF6FD8, 0xC2449E),   // magenta
        (0.38, 0x7B6CFF, 0x4B3BD6),   // violet
    ]
    let wellWidth: CGFloat = 158, gap: CGFloat = 54
    let wellHeight: CGFloat = 560
    let startX = 512 - (wellWidth * 3 + gap * 2) / 2
    let wellY: CGFloat = 232
    for (index, fader) in faders.enumerated() {
        let x = startX + CGFloat(index) * (wellWidth + gap)
        let well = CGRect(x: x, y: wellY, width: wellWidth, height: wellHeight)
        let wellPath = CGPath(roundedRect: well, cornerWidth: 34, cornerHeight: 34, transform: nil)
        // Recessed slot.
        ctx.addPath(wellPath); ctx.setFillColor(color(0x121110)); ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(wellPath); ctx.clip()
        // Detent lines at 25 / 50 / 75 %.
        ctx.setFillColor(color(0x2E2B27))
        for mark in [0.25, 0.5, 0.75] as [CGFloat] {
            ctx.fill(CGRect(x: x + 30, y: wellY + wellHeight * mark - 3, width: wellWidth - 60, height: 6))
        }
        // The fill and its white cap.
        let fillHeight = wellHeight * fader.level
        ctx.saveGState()
        let fill = CGRect(x: x, y: wellY, width: wellWidth, height: fillHeight)
        let gradient = CGGradient(colorsSpace: space, colors: [color(fader.top), color(fader.bottom)] as CFArray, locations: [0, 1])!
        ctx.addRect(fill); ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: wellY + fillHeight), end: CGPoint(x: 0, y: wellY), options: [])
        ctx.restoreGState()
        // Light spilling up into the empty part of the slot.
        let spill = CGGradient(colorsSpace: space, colors: [color(fader.top, 0.45), color(fader.top, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(spill, start: CGPoint(x: 0, y: wellY + fillHeight), end: CGPoint(x: 0, y: wellY + fillHeight + 170), options: [])
        ctx.setFillColor(color(0xFFFFFF, 0.95))
        ctx.fill(CGRect(x: x, y: wellY + fillHeight - 7, width: wellWidth, height: 14))
        ctx.restoreGState()
        // Rim.
        ctx.addPath(wellPath); ctx.setStrokeColor(color(0x000000, 0.35)); ctx.setLineWidth(4); ctx.strokePath()
    }
    // Hairline highlight along the tile's top edge.
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.08)); ctx.setLineWidth(3); ctx.strokePath()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try writePNG(drawIcon(size: 1024), to: output.appendingPathComponent("AppIcon-1024.png"))

// Every size macOS asks for, drawn natively rather than downscaled.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for base in [16, 32, 128, 256, 512] {
    try writePNG(drawIcon(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(drawIcon(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)/AppIcon.icns")
