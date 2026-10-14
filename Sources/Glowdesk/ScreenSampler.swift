import Foundation
import ScreenCaptureKit
import CoreGraphics

/// Grabs a tiny snapshot of the main display and reduces it to one representative color.
@MainActor final class ScreenSampler {
    private var filter: SCContentFilter?

    struct Sample { let rgb: RGB; let luminance: Double }

    func sample() async throws -> Sample {
        if filter == nil {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                throw HueError.message(t("No display found."))
            }
            // Leave this app's own panel out of the picture.
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        let configuration = SCStreamConfiguration()
        configuration.width = 64
        configuration.height = 36
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter!, configuration: configuration)
        return Self.reduce(image)
    }

    /// Saturated, bright pixels count more, so a colorful subject beats a gray background.
    nonisolated static func reduce(_ image: CGImage) -> Sample {
        let width = 32, height = 18
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0, luminance = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            let weight = 0.04 + saturation * maxC * maxC
            r += pr * weight; g += pg * weight; b += pb * weight; total += weight
            luminance += 0.2126 * pr + 0.7152 * pg + 0.0722 * pb
        }
        let count = Double(width * height)
        guard total > 0 else { return Sample(rgb: RGB(r: 1, g: 1, b: 1), luminance: 0) }
        let mean = RGB(r: r / total, g: g / total, b: b / total)
        let hs = mean.hueSaturation
        return Sample(rgb: .hsb(hs.hue, min(1, hs.saturation * 1.15), 1), luminance: luminance / count)
    }
}
