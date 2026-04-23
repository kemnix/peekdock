import Foundation
import CoreGraphics
import AppKit
import os.log

private let logger = Logger(subsystem: "dev.kemnix.peekdock", category: "Coordinator")

@MainActor
@Observable
final class AppCoordinator {
    let appState = AppState()

    private let zoomMonitor: ZoomMonitor
    private let captureManager: ScreenCaptureManager
    private let diffEngine = DiffEngine()
    private let storage = CaptureStorage()
    private let regionSelector = RegionSelectorWindowController()
    private let reviewWindow = ReviewWindowController()

    init() {
        let state = appState
        self.zoomMonitor = ZoomMonitor(appState: state)
        self.captureManager = ScreenCaptureManager(appState: state)
    }

    func start() {
        zoomMonitor.start()
        Task {
            await captureManager.checkPermission()
        }
    }

    func toggleCapture() {
        if appState.isCapturing {
            stopCapture()
        } else {
            beginRegionSelection()
        }
    }

    // MARK: - Region Selection

    private func beginRegionSelection() {
        guard appState.isZoomRunning else {
            appState.statusMessage = LocalizationManager.shared.t("status.zoomNotRunning")
            return
        }
        guard appState.hasScreenCapturePermission else {
            appState.statusMessage = LocalizationManager.shared.t("status.permissionRequired")
            return
        }

        appState.isSelectingRegion = true
        appState.statusMessage = LocalizationManager.shared.t("status.selectArea")

        Task {
            do {
                let snapshot = try await captureManager.takeZoomSnapshot()
                regionSelector.show(
                    snapshot: snapshot,
                    onConfirm: { [weak self] region in
                        Task { @MainActor in
                            self?.onRegionSelected(region)
                        }
                    },
                    onCancel: { [weak self] in
                        Task { @MainActor in
                            self?.onRegionCancelled()
                        }
                    }
                )
            } catch {
                logger.error("Failed to take snapshot: \(error.localizedDescription)")
                appState.isSelectingRegion = false
                appState.statusMessage = LocalizationManager.shared.t("status.snapshotFailed", error.localizedDescription)
            }
        }
    }

    private func onRegionSelected(_ region: CGRect) {
        appState.isSelectingRegion = false
        appState.captureRegion = region
        captureManager.cropRegion = region
        startCapture()
    }

    private func onRegionCancelled() {
        appState.isSelectingRegion = false
        appState.statusMessage = appState.isZoomRunning ? LocalizationManager.shared.t("status.zoomActive") : LocalizationManager.shared.t("status.waitingForZoom")
    }

    // MARK: - Capture

    private func startCapture() {
        appState.isCapturing = true
        appState.statusMessage = LocalizationManager.shared.t("status.capturing")
        diffEngine.reset()

        // Create session directory on main thread (it's fast I/O)
        do {
            let sessionPath = try storage.startSession()
            appState.sessionDirectory = sessionPath
            appState.captureCount = 0
        } catch {
            logger.error("Failed to create session: \(error.localizedDescription)")
            appState.isCapturing = false
            appState.statusMessage = LocalizationManager.shared.t("status.sessionFailed")
            return
        }

        Task {
            do {
                try await captureManager.startCapture { [weak self] image in
                    self?.handleFrame(image)
                }
            } catch {
                logger.error("Failed to start capture: \(error.localizedDescription)")
                await MainActor.run {
                    self.appState.isCapturing = false
                    self.appState.statusMessage = LocalizationManager.shared.t("status.captureFailed", error.localizedDescription)
                }
            }
        }
    }

    func stopCapture() {
        appState.isCapturing = false
        appState.statusMessage = appState.isZoomRunning ? LocalizationManager.shared.t("status.zoomActive") : LocalizationManager.shared.t("status.waitingForZoom")

        let sessionDir = appState.sessionDirectory
        let slideCount = appState.captureCount

        Task {
            await captureManager.stopCapture()
        }

        storage.endSession()

        // Show review window if we have slides
        if let sessionDir = sessionDir, slideCount > 0 {
            showReview(sessionDirectory: sessionDir)
        }
    }

    private func showReview(sessionDirectory: String) {
        let sessionURL = URL(fileURLWithPath: sessionDirectory)
        reviewWindow.onShouldCancel = { [weak self] in
            Task { @MainActor in
                await self?.cleanupTempFiles()
            }
        }

        reviewWindow.show(sessionDirectory: sessionURL) { [weak self] options in
            self?.handleExport(options: options)
        } onCancel: {
        }
    }

    private func handleExport(options: ReviewExportOptions) {
        Task {
            do {
                try PdfExporter.export(slides: options.slides, format: options.format, destination: options.destination)
                await MainActor.run {
                    appState.statusMessage = LocalizationManager.shared.t("status.exportCompleted")
                }

                // Clean up temp files after successful export
                await cleanupTempFiles()
            } catch {
                logger.error("Export failed: \(error.localizedDescription)")
                await MainActor.run {
                    appState.statusMessage = LocalizationManager.shared.t("status.exportFailed", error.localizedDescription)
                }
            }
        }
    }

    private func hideReviewWindow() {
        reviewWindow.close()
    }

    private func cleanupTempFiles() async {
        if let sessionDir = appState.sessionDirectory {
            storage.cleanupSession(at: sessionDir)
            await MainActor.run {
                appState.sessionDirectory = nil
            }
        }
    }

    // MARK: - Frame Handling (called from background thread)

    private nonisolated func handleFrame(_ image: CGImage) {
        if diffEngine.detectChange(in: image) {
            do {
                _ = try storage.save(image: image)
                // Create thumbnail for preview
                let thumb = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        self.appState.captureCount = self.storage.currentSlideCount
                        self.appState.lastCaptureTime = Date()
                        self.appState.lastCapturedImage = thumb
                    }
                }
            } catch {
                logger.error("Failed to save capture: \(error.localizedDescription)")
            }
        }
    }
}
