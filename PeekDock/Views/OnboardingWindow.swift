import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: OnboardingWindow?
    var onFinish: (() -> Void)?

    func show(startStep: OnboardingStep = .welcome) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = OnboardingView(startStep: startStep) { [weak self] in
            self?.finish()
        }
        .environment(LocalizationManager.shared)

        let hostingView = NSHostingView(rootView: rootView)

        let windowWidth: CGFloat = 560
        let windowHeight: CGFloat = 420

        guard let screen = NSScreen.main else { return }
        let rect = NSRect(
            x: screen.frame.midX - windowWidth / 2,
            y: screen.frame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        let window = OnboardingWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .normal
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    private func finish() {
        close()
        onFinish?()
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
