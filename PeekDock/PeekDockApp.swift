import SwiftUI

@main
struct PeekDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: appDelegate.coordinator)
                .environment(LocalizationManager.shared)
        } label: {
            Image(systemName: "eye.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}

private let onboardingCompletedKey = "dev.kemnix.peekdock.hasCompletedOnboarding"
private let onboardingAgreedToTermsKey = "dev.kemnix.peekdock.hasAgreedToTerms"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private let notchWindow = NotchWindowController()
    private let onboardingWindow = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()

        let defaults = UserDefaults.standard
        let completedOnboarding = defaults.bool(forKey: onboardingCompletedKey)
        let agreedToTerms = defaults.bool(forKey: onboardingAgreedToTermsKey)
        let hasPermission = CGPreflightScreenCaptureAccess()

        if !completedOnboarding {
            showNotch()
            onboardingWindow.onFinish = {
                defaults.set(true, forKey: onboardingCompletedKey)
                defaults.removeObject(forKey: onboardingAgreedToTermsKey)
            }
            onboardingWindow.show(startStep: resumeStep(agreedToTerms: agreedToTerms, hasPermission: hasPermission))
        } else if !hasPermission {
            showNotch()
            onboardingWindow.onFinish = {}
            onboardingWindow.show(startStep: .permission)
        } else {
            showNotch()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func resumeStep(agreedToTerms: Bool, hasPermission: Bool) -> OnboardingStep {
        if agreedToTerms && hasPermission { return .tutorial }
        if agreedToTerms { return .permission }
        return .welcome
    }

    private func showNotch() {
        notchWindow.show(
            appState: coordinator.appState,
            onToggleCapture: { [weak self] in
                self?.coordinator.toggleCapture()
            }
        )
    }
}

struct MenuBarView: View {
    let coordinator: AppCoordinator
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        Text(coordinator.appState.isZoomRunning ? l10n.t("menu.zoomRunning") : l10n.t("menu.zoomNotRunning"))

        if coordinator.appState.isCapturing {
            Text(l10n.t("menu.capturingCount", coordinator.appState.captureCount))
        }

        Divider()

        Button(coordinator.appState.isCapturing ? l10n.t("menu.stopCapture") : l10n.t("menu.startCapture")) {
            coordinator.toggleCapture()
        }
        .disabled(!coordinator.appState.isZoomRunning)

        Divider()

        Menu(l10n.t("menu.language")) {
            ForEach(LocalizationManager.supportedLanguages, id: \.code) { lang in
                Button {
                    l10n.language = lang.code
                } label: {
                    HStack {
                        Text(lang.label)
                        if l10n.language == lang.code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button(l10n.t("button.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
