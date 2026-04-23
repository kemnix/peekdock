import Accelerate
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "dev.kemnix.peekdock", category: "DiffEngine")

final class DiffEngine {
    private var previousGrayscale: [UInt8]?
    private var previousWidth = 0
    private var previousHeight = 0
    private var lastTriggerTime: Date?

    /// Difference threshold (0.0–1.0). Lower = more sensitive.
    var threshold: Double = 0.02

    /// Minimum seconds between triggers.
    var cooldown: TimeInterval = 2.0

    /// Returns true if the frame differs significantly from the previous one.
    func detectChange(in image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        let pixelCount = width * height

        guard let grayscale = toGrayscale(image, width: width, height: height) else {
            return false
        }

        defer {
            previousGrayscale = grayscale
            previousWidth = width
            previousHeight = height
        }

        guard let prev = previousGrayscale,
              previousWidth == width,
              previousHeight == height else {
            // First frame or resolution changed — treat as change
            return true
        }

        // Compute mean absolute difference
        var diffSum: Int = 0
        for i in 0..<pixelCount {
            let a = Int(prev[i])
            let b = Int(grayscale[i])
            diffSum += abs(a - b)
        }

        let meanDiff = Double(diffSum) / Double(pixelCount) / 255.0

        guard meanDiff >= threshold else {
            return false
        }

        // Cooldown check
        if let last = lastTriggerTime, Date().timeIntervalSince(last) < cooldown {
            return false
        }

        lastTriggerTime = Date()
        logger.info("Slide change detected (diff: \(String(format: "%.3f", meanDiff)))")
        return true
    }

    func reset() {
        previousGrayscale = nil
        lastTriggerTime = nil
    }

    // MARK: - Private

    private func toGrayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let pixelCount = width * height

        // Draw CGImage into 8-bit grayscale buffer
        var pixels = [UInt8](repeating: 0, count: pixelCount)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
