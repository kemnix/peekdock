import AppKit
import SwiftUI

final class RegionSelectorWindowController {
    private var window: KeyWindow?
    private var hasResolved = false

    @MainActor func show(snapshot: NSImage, onConfirm: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        guard let screen = NSScreen.main else { return }

        hasResolved = false

        let view = RegionSelectorView(
            snapshot: snapshot,
            zoomWindowSize: nil,
            onConfirm: { [weak self] rect in
                DispatchQueue.main.async {
                    self?.hasResolved = true
                    self?.close()
                    onConfirm(rect)
                }
            },
            onCancel: { [weak self] in
                DispatchQueue.main.async {
                    self?.hasResolved = true
                    self?.close()
                    onCancel()
                }
            }
        )
        .environment(LocalizationManager.shared)

        let hostingView = NSHostingView(rootView: view)

        let windowRect = computeWindowRect(for: snapshot.size, on: screen)

        let window = KeyWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = LocalizationManager.shared.t("region.window.title")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = hostingView

        window.onEscape = { [weak self] in
            DispatchQueue.main.async {
                self?.hasResolved = true
                self?.close()
                onCancel()
            }
        }
        window.onEnter = {
            NotificationCenter.default.post(name: .regionSelectorConfirm, object: nil)
        }
        window.onCloseRequested = { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.hasResolved else { return }
                self.hasResolved = true
                self.close()
                onCancel()
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    private func computeWindowRect(for snapshotSize: CGSize, on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let maxWidth = visibleFrame.width * 0.7
        let maxHeight = visibleFrame.height * 0.7
        let aspect = snapshotSize.width / max(snapshotSize.height, 1)

        var width = min(snapshotSize.width, maxWidth)
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}

final class KeyWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onEnter: (() -> Void)?
    var onCloseRequested: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onEscape?()
        case 36, 76:
            onEnter?()
        default:
            super.keyDown(with: event)
        }
    }

    override func performClose(_ sender: Any?) {
        if let handler = onCloseRequested {
            handler()
        } else {
            super.performClose(sender)
        }
    }
}

extension Notification.Name {
    static let regionSelectorConfirm = Notification.Name("regionSelectorConfirm")
}
