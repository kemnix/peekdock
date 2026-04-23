import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class AppState {
    var isZoomRunning = false
    var isInMeeting = false
    var isCapturing = false
    var lastCaptureTime: Date?
    var captureCount = 0
    var sessionDirectory: String?
    var hasScreenCapturePermission = false
    var statusMessage = LocalizationManager.shared.t("status.waitingForZoom")
    var isSelectingRegion = false

    /// Normalized crop rect (0–1) relative to the Zoom window. nil = full window.
    var captureRegion: CGRect?

    /// Thumbnail of the last captured slide for preview.
    var lastCapturedImage: NSImage?

    var timeSinceLastCapture: String {
        guard let last = lastCaptureTime else { return "—" }
        let interval = Date().timeIntervalSince(last)
        if interval < 60 {
            return LocalizationManager.shared.t("time.secondsAgo", Int(interval))
        } else {
            return LocalizationManager.shared.t("time.minutesAgo", Int(interval / 60))
        }
    }
}
