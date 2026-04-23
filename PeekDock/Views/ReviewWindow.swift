import AppKit
import SwiftUI

@MainActor
final class ReviewWindowController {
    private var window: ReviewPanel?
    private var isOpen = false
    var onShow: (() -> Void)?
    var onClose: (() -> Void)?
    var onShouldCancel: (() -> Void)?

    func show(sessionDirectory: URL, onSave: @escaping (ReviewExportOptions) -> Void, onCancel: @escaping () -> Void) {
        let session = ReviewSession()

        do {
            try session.loadSlides(from: sessionDirectory)
        } catch {
            print("Failed to load slides: \(error)")
            onCancel()
            return
        }

        let reviewView = ReviewView(
            session: session,
            onSave: { [weak self] options in
                self?.close()
                onSave(options)
            },
            onCancel: { [weak self] in
                self?.attemptCancel()
            }
        )
        let rootView = reviewView.environment(LocalizationManager.shared)

        let hostingView = NSHostingView(rootView: rootView)

        guard let screen = NSScreen.main else { return }

        let windowWidth: CGFloat = 1000
        let windowHeight: CGFloat = 700
        let windowRect = NSRect(
            x: screen.frame.midX - windowWidth / 2,
            y: screen.frame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        let window = ReviewPanel(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = LocalizationManager.shared.t("review.window.title")
        window.isFloatingPanel = true // Make it a floating panel
        window.level = .floating // Use floating level to stay visible above other windows
        window.isMovableByWindowBackground = false // Disable background movement
        window.hidesOnDeactivate = false // Don't hide when other apps become active
        window.contentView = hostingView
        window.backgroundColor = .black

        // Set key handler for keyboard shortcuts
        window.keyHandler = { key in
            reviewView.handleKeyPress(key)
        }

        // Set close handler for window close button
        window.shouldCloseHandler = { [weak self] in
            return self?.attemptCancel() ?? false
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        isOpen = true

        // Trigger show callback
        onShow?()
    }

    @discardableResult
    private func attemptCancel() -> Bool {
        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.t("review.discard.title")
        alert.informativeText = LocalizationManager.shared.t("review.discard.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: LocalizationManager.shared.t("review.discard.confirm"))
        alert.addButton(withTitle: LocalizationManager.shared.t("button.cancel"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            onShouldCancel?()
            close()
            return true
        }
        return false
    }

    func close() {
        isOpen = false
        window?.close()
        window = nil

        // Trigger close callback
        onClose?()
    }
}

// Custom panel subclass for keyboard handling
final class ReviewPanel: NSPanel {
    var keyHandler: ((String) -> Void)?
    var shouldCloseHandler: (() -> Bool)?

    override var canBecomeKey: Bool { true }

    override var worksWhenModal: Bool {
        get { true }
        set { }
    }

    override func performClose(_ sender: Any?) {
        // Trigger the cancel handler instead of immediately closing
        if let handler = shouldCloseHandler {
            let shouldClose = handler()
            if shouldClose {
                super.performClose(sender)
            }
        } else {
            super.performClose(sender)
        }
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        keyHandler?(key)

        // Handle common keyboard shortcuts (suppress system sounds)
        if event.keyCode == 53 { // Escape
            performClose(nil)
        } else {
            // Don't call super to avoid keyboard sounds
            // System sounds are handled through NSEvent's default behavior
        }
    }
}

struct ReviewExportOptions {
    let slides: [SlideItem]
    let format: ExportFormat
    let destination: URL
}
