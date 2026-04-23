import ScreenCaptureKit
import CoreImage
import AppKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "dev.kemnix.peekdock", category: "ScreenCapture")

final class ScreenCaptureManager: NSObject, SCStreamOutput {
    private let appState: AppState
    private var stream: SCStream?
    private var onFrame: ((CGImage) -> Void)?
    private let ciContext = CIContext()  // reuse across frames

    /// Normalized crop region (0–1). nil = full window.
    var cropRegion: CGRect?

    init(appState: AppState) {
        self.appState = appState
    }

    func checkPermission() async {
        let granted = CGPreflightScreenCaptureAccess()
        await MainActor.run {
            appState.hasScreenCapturePermission = granted
        }
    }

    /// Take a single snapshot of the Zoom window for region selection.
    func takeZoomSnapshot() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let zoomWindow = findZoomWindow(in: content) else {
            throw CaptureError.zoomWindowNotFound
        }

        let scale = scaleFactor(for: zoomWindow)
        logger.info("Snapshot target: '\(zoomWindow.title ?? "Untitled")' \(Int(zoomWindow.frame.width))x\(Int(zoomWindow.frame.height)) @ \(scale)x")

        let filter = SCContentFilter(desktopIndependentWindow: zoomWindow)
        let config = SCStreamConfiguration()
        config.width = Int(zoomWindow.frame.width * scale)
        config.height = Int(zoomWindow.frame.height * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        logger.info("Snapshot produced: \(cgImage.width)x\(cgImage.height), bitsPerPixel: \(cgImage.bitsPerPixel)")

        return NSImage(cgImage: cgImage, size: NSSize(width: zoomWindow.frame.width, height: zoomWindow.frame.height))
    }

    private func scaleFactor(for window: SCWindow) -> CGFloat {
        let winFrame = window.frame
        let screen = NSScreen.screens.first { screen in
            let flipped = CGRect(
                x: winFrame.origin.x,
                y: screen.frame.maxY - winFrame.origin.y - winFrame.height,
                width: winFrame.width,
                height: winFrame.height
            )
            return screen.frame.intersects(flipped)
        } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2.0
    }

    func startCapture(onFrame: @escaping (CGImage) -> Void) async throws {
        self.onFrame = onFrame

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let zoomWindow = findZoomWindow(in: content) else {
            throw CaptureError.zoomWindowNotFound
        }

        logger.info("Capturing Zoom window: \(zoomWindow.title ?? "untitled") (\(Int(zoomWindow.frame.width))x\(Int(zoomWindow.frame.height)))")

        let filter = SCContentFilter(desktopIndependentWindow: zoomWindow)

        let config = SCStreamConfiguration()
        config.width = Int(zoomWindow.frame.width)
        config.height = Int(zoomWindow.frame.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2) // 0.5fps
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))
        try await newStream.startCapture()

        self.stream = newStream
        logger.info("Screen capture started")
    }

    func stopCapture() async {
        guard let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            logger.error("Failed to stop capture: \(error.localizedDescription)")
        }
        self.stream = nil
        self.onFrame = nil
        logger.info("Screen capture stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        guard let imageBuffer = sampleBuffer.imageBuffer else {
            logger.debug("No image buffer in sample")
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard var cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            logger.debug("Failed to create CGImage from CIImage")
            return
        }

        // Apply crop if region is set
        if let region = cropRegion {
            let w = CGFloat(cgImage.width)
            let h = CGFloat(cgImage.height)
            let cropRect = CGRect(
                x: region.origin.x * w,
                y: region.origin.y * h,
                width: region.width * w,
                height: region.height * h
            ).integral

            if cropRect.width > 0, cropRect.height > 0,
               let cropped = cgImage.cropping(to: cropRect) {
                cgImage = cropped
            }
        }

        onFrame?(cgImage)
    }

    // MARK: - Private

    private func findZoomWindow(in content: SCShareableContent) -> SCWindow? {
        let zoomWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == "us.zoom.xos"
            && $0.isOnScreen
            && $0.frame.width > 200
            && $0.frame.height > 200
        }

        logger.info("Found \(zoomWindows.count) Zoom windows:")
        for window in zoomWindows {
            logger.info("  Title: '\(window.title ?? "Untitled")', Size: \(Int(window.frame.width))x\(Int(window.frame.height))")
        }

        let meetingKeywords = ["Meeting", "ミーティング", "meeting", "Zoom Meeting", "共有", "Share", "Screen Share"]
        let excludedKeywords = ["Workplace", "Home", "Settings", "Preferences", "設定", "Chat", "チャット", "Contacts", "連絡先"]

        let meetingMatches = zoomWindows.filter { window in
            guard let title = window.title, !title.isEmpty else { return false }
            if excludedKeywords.contains(where: { title.localizedCaseInsensitiveContains($0) }) { return false }
            return meetingKeywords.contains(where: { title.localizedCaseInsensitiveContains($0) })
        }

        if let chosen = meetingMatches.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            logger.info("Selected meeting window by title: '\(chosen.title ?? "")'")
            return chosen
        }

        let filtered = zoomWindows.filter { window in
            guard let title = window.title else { return true }
            return !excludedKeywords.contains(where: { title.localizedCaseInsensitiveContains($0) })
        }
        let fallback = (filtered.isEmpty ? zoomWindows : filtered)
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        if let fallback {
            logger.info("Selected largest non-excluded window: '\(fallback.title ?? "Untitled")'")
        }
        return fallback
    }
}

enum CaptureError: LocalizedError {
    case zoomWindowNotFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .zoomWindowNotFound: MainActor.assumeIsolated { LocalizationManager.shared.t("error.zoomWindowNotFound") }
        case .permissionDenied: MainActor.assumeIsolated { LocalizationManager.shared.t("error.permissionDenied") }
        }
    }
}
