import Foundation
import AppKit
import SwiftUI

struct RGB: Hashable, Codable {
    var r: Double, g: Double, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    func distance(to other: RGB) -> Double { abs(r - other.r) + abs(g - other.g) + abs(b - other.b) }
    /// Perceived lightness (Rec. 709 weights on sRGB values), 0…1.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    /// Hue (0…1) and saturation (0…1), for placing a marker on the color pad.
    var hueSaturation: (hue: Double, saturation: Double) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return (Double(c.hueComponent), Double(c.saturationComponent))
    }
    static func hsb(_ h: Double, _ s: Double, _ b: Double) -> RGB {
        let c = NSColor(hue: h, saturation: s, brightness: b, alpha: 1).usingColorSpace(.sRGB)!
        return RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}

/// Conversions published by Philips for Hue lights (Wide RGB D65 primaries).
enum ColorMath {
    static func xyToRGB(_ xy: XY) -> RGB {
        let y = max(xy.y, 0.0001), Y = 1.0
        let X = Y / y * xy.x, Z = Y / y * (1 - xy.x - xy.y)
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530
        r = max(r, 0); g = max(g, 0); b = max(b, 0)
        let peak = max(r, g, b, 0.0001)
        r /= peak; g /= peak; b /= peak
        func gamma(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        return RGB(r: min(1, max(0, gamma(r))), g: min(1, max(0, gamma(g))), b: min(1, max(0, gamma(b))))
    }

    static func rgbToXY(_ rgb: RGB) -> XY {
        func linear(_ v: Double) -> Double { v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92 }
        let r = linear(rgb.r), g = linear(rgb.g), b = linear(rgb.b)
        let X = r * 0.664511 + g * 0.154324 + b * 0.162028
        let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let sum = X + Y + Z
        guard sum > 0 else { return XY(x: 0.3227, y: 0.329) }
        return XY(x: (X / sum * 10000).rounded() / 10000, y: (Y / sum * 10000).rounded() / 10000)
    }

    /// Approximate black-body color for a mirek value (1,000,000 / kelvin).
    static func mirekToRGB(_ mirek: Int) -> RGB {
        let temp = 1_000_000 / Double(max(mirek, 1)) / 100
        let r = temp <= 66 ? 255 : 329.698727446 * pow(temp - 60, -0.1332047592)
        let g = temp <= 66 ? 99.4708025861 * log(temp) - 161.1195681661 : 288.1221695283 * pow(temp - 60, -0.0755148492)
        let b = temp >= 66 ? 255 : temp <= 19 ? 0 : 138.5177312231 * log(temp - 10) - 305.0447927307
        func clamp(_ v: Double) -> Double { min(1, max(0, v / 255)) }
        return RGB(r: clamp(r), g: clamp(g), b: clamp(b))
    }

    static func kelvin(_ mirek: Int) -> Int { Int((1_000_000 / Double(max(mirek, 1)) / 100).rounded()) * 100 }

    /// A vivid version of the average color of the lit bulbs, used as the panel accent.
    static func accent(for colors: [RGB]) -> RGB? {
        guard !colors.isEmpty else { return nil }
        let n = Double(colors.count)
        let mean = RGB(r: colors.map(\.r).reduce(0, +) / n, g: colors.map(\.g).reduce(0, +) / n, b: colors.map(\.b).reduce(0, +) / n)
        let hs = mean.hueSaturation
        return .hsb(hs.hue, min(1, max(0.45, hs.saturation * 1.25)), 1)
    }
}
