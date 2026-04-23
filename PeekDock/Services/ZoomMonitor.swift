import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class ZoomMonitor {
    private static let zoomBundleID = "us.zoom.xos"
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Initial check
        appState.isZoomRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.zoomBundleID
        }
        updateStatus()

        // Launch notification
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.bundleIdentifier == Self.zoomBundleID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkZoomWindowState()
            }
            .store(in: &cancellables)

        // Terminate notification
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.bundleIdentifier == Self.zoomBundleID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appState.isZoomRunning = false
                self?.appState.isCapturing = false
                self?.updateStatus()
            }
            .store(in: &cancellables)

        // Periodic check for window state changes
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkZoomWindowState()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    private func checkZoomWindowState() {
        guard appState.isZoomRunning else { return }

        let hasPermission = CGPreflightScreenCaptureAccess()
        if hasPermission != appState.hasScreenCapturePermission {
            appState.hasScreenCapturePermission = hasPermission
        }
        guard hasPermission else { return }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let zoomWindows = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == Self.zoomBundleID
                    && $0.isOnScreen
                }

                // Check if any window indicates a meeting is active
                let isMeetingActive = zoomWindows.contains { window in
                    isMeetingWindow(title: window.title)
                }

                await MainActor.run {
                    appState.isZoomRunning = true
                    appState.isInMeeting = isMeetingActive
                    updateStatus()
                }
            } catch {
                // Screen capture permission not granted yet, ignore
            }
        }
    }

    private func isMeetingWindow(title: String?) -> Bool {
        guard let title = title else { return false }

        // Common patterns for meeting windows
        let meetingKeywords = ["meeting", "zoom meeting", "join", "participants", "share", "record"]

        return meetingKeywords.contains { keyword in
            title.lowercased().contains(keyword)
        }
    }

    private func updateStatus() {
        if appState.isZoomRunning {
            appState.statusMessage = appState.isCapturing ? LocalizationManager.shared.t("status.capturing") : LocalizationManager.shared.t("status.zoomActive")
        } else {
            appState.statusMessage = LocalizationManager.shared.t("status.waitingForZoom")
        }
    }
}
