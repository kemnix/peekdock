import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var viewModel: NotchViewModel?

    private static let notchHalfWidth: CGFloat = 92  // +2 to cover notch edge
    private static let eyeWidth: CGFloat = 64
    private static let totalWidth: CGFloat = notchHalfWidth * 2 + eyeWidth
    private static let topRowHeight: CGFloat = 32
    private static let drawerHeight: CGFloat = 48
    private static let maxHeight: CGFloat = topRowHeight + drawerHeight

    func show(appState: AppState, onToggleCapture: @escaping () -> Void) {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else { return }

        let vm = NotchViewModel(appState: appState)
        self.viewModel = vm

        let sf = screen.frame
        let x = sf.midX - Self.notchHalfWidth
        // Panel always max height, pinned to top. SwiftUI controls visible content.
        let y = sf.maxY - Self.maxHeight

        let rootView = NotchUnifiedView(vm: vm, appState: appState, onToggleCapture: onToggleCapture)
            .environment(LocalizationManager.shared)
        let hosting = NSHostingView(rootView: rootView)

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: Self.totalWidth, height: Self.maxHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.contentView = hosting
        p.orderFrontRegardless()
        self.panel = p

        // Hover: only trigger on the top row (eye area)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self, weak vm] _ in self?.updateHover(vm: vm)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self, weak vm] event in
            self?.updateHover(vm: vm)
            return event
        }
    }

    func close() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil; viewModel = nil
    }

    private func updateHover(vm: NotchViewModel?) {
        guard let vm, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let pf = panel.frame

        // Top row rect (the notch bar with eyes)
        let topRow = NSRect(x: pf.minX, y: pf.maxY - Self.topRowHeight,
                            width: pf.width, height: Self.topRowHeight)
        let inTopRow = topRow.contains(mouse)
        let inPanelBounds = pf.contains(mouse)

        DispatchQueue.main.async {
            // Keep expanded while cursor is anywhere in the panel
            let inPanel = vm.isExpanded && inPanelBounds
            let shouldReceiveEvents = inTopRow || inPanel
            vm.isHovering = shouldReceiveEvents
            if panel.ignoresMouseEvents != !shouldReceiveEvents {
                panel.ignoresMouseEvents = !shouldReceiveEvents
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class NotchViewModel {
    var isHovering = false

    private let appState: AppState
    private var collapseTask: DispatchWorkItem?

    init(appState: AppState) { self.appState = appState }

    var isExpanded: Bool { appState.isCapturing || isHovering }

    func hoverChanged() {
        collapseTask?.cancel()
        if !isExpanded {
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // triggers SwiftUI re-evaluation via isHovering
                _ = self.isExpanded
            }
            collapseTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
    }
}

// MARK: - Unified View

struct NotchUnifiedView: View {
    let vm: NotchViewModel
    let appState: AppState
    let onToggleCapture: () -> Void
    @Environment(LocalizationManager.self) private var l10n

    private var eyeState: EyeState {
        if appState.isCapturing { return .active }
        if appState.isZoomRunning { return .focused }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top row: notch fill + eyes (fixed, never moves) ──
            topRow
                .frame(height: 32)

            // ── Drawer ──
            if vm.isExpanded {
                drawer
                    .frame(height: 48)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .clipShape(NotchShape(expanded: vm.isExpanded))
        .animation(.spring(duration: 0.3, bounce: 0.1), value: vm.isExpanded)
        .onChange(of: vm.isHovering) { _, _ in vm.hoverChanged() }
        .onChange(of: appState.isCapturing) { _, _ in vm.hoverChanged() }
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                EyeAnimationView(state: eyeState)
                if appState.isCapturing {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                        .padding(.leading, 5)
                        .shadow(color: .red.opacity(0.8), radius: 3)
                }
            }
            .frame(width: 64)
        }
    }

    private var drawer: some View {
        HStack(spacing: 8) {
            if appState.isCapturing, let thumb = appState.lastCapturedImage {
                // Slide thumbnail preview
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("notch.slidesCount", appState.captureCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(appState.timeSinceLastCapture)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
            } else {
                // Status text (non-capturing state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.statusMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onToggleCapture) {
                    Text(buttonLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(buttonColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!appState.isZoomRunning || !appState.hasScreenCapturePermission || appState.isSelectingRegion)
                .opacity(isButtonEnabled ? 1.0 : 0.4)

                if !appState.isCapturing {
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Text(l10n.t("button.quit"))
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var buttonLabel: String {
        if appState.isSelectingRegion { return l10n.t("notch.selecting") }
        if appState.isCapturing { return l10n.t("notch.stop") }
        return l10n.t("notch.capture")
    }

    private var buttonColor: Color {
        if appState.isSelectingRegion { return .orange.opacity(0.8) }
        if appState.isCapturing { return .red.opacity(0.8) }
        if appState.isInMeeting { return .green.opacity(0.8) }
        return .gray.opacity(0.8)
    }

    private var isButtonEnabled: Bool {
        appState.isZoomRunning && appState.hasScreenCapturePermission && !appState.isSelectingRegion
    }
}

// MARK: - Shape

struct NotchShape: Shape {
    var contentHeight: CGFloat

    var animatableData: CGFloat {
        get { contentHeight }
        set { contentHeight = newValue }
    }

    init(expanded: Bool) {
        self.contentHeight = expanded ? 80 : 32
    }

    func path(in rect: CGRect) -> Path {
        let h = contentHeight
        let r: CGFloat = min(14, h / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY + h),
                        control: CGPoint(x: rect.maxX, y: rect.minY + h))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + h))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + h - r),
                        control: CGPoint(x: rect.minX, y: rect.minY + h))
        p.closeSubpath()
        return p
    }
}
