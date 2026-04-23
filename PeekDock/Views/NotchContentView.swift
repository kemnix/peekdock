import SwiftUI

struct NotchContentView: View {
    let appState: AppState
    let onToggleCapture: () -> Void

    private var eyeState: EyeState {
        if appState.isCapturing { return .active }
        if appState.isZoomRunning { return .focused }
        return .idle
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left: Eyes
            EyeAnimationView(state: eyeState)

            // Center: Status
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)

                if appState.isCapturing {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("Slides: \(appState.captureCount) · \(appState.timeSinceLastCapture)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: Toggle + Indicator
            HStack(spacing: 8) {
                if appState.isCapturing {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: .red.opacity(0.6), radius: 4)
                }

                Button(action: onToggleCapture) {
                    Text(buttonLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(buttonColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!appState.isZoomRunning || !appState.hasScreenCapturePermission || appState.isSelectingRegion)
                .opacity(isButtonEnabled ? 1.0 : 0.4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 340, height: 44)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    private var buttonLabel: String {
        if appState.isSelectingRegion { return "Selecting..." }
        if appState.isCapturing { return "Stop" }
        return "Capture"
    }

    private var buttonColor: Color {
        if appState.isSelectingRegion { return .orange.opacity(0.8) }
        if appState.isCapturing { return .red.opacity(0.8) }
        return .green.opacity(0.8)
    }

    private var isButtonEnabled: Bool {
        appState.isZoomRunning && appState.hasScreenCapturePermission && !appState.isSelectingRegion
    }
}
