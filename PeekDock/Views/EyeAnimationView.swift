import SwiftUI

enum EyeState: Equatable {
    case idle       // Zoom未起動 — キョロキョロ
    case focused    // Zoom起動中 — 収束停止
    case active     // キャプチャ中 — 細目でじっと見る
}

struct EyeAnimationView: View {
    let state: EyeState

    @State private var pupilOffset: CGSize = .zero
    @State private var animationID = UUID()

    private let eyeWidth: CGFloat = 16
    private let pupilSize: CGFloat = 7

    private var eyeHeight: CGFloat {
        state == .active ? 9 : 16
    }

    var body: some View {
        HStack(spacing: 6) {
            singleEye
            singleEye
        }
        .onAppear { scheduleAnimation() }
        .onChange(of: state) { _, _ in scheduleAnimation() }
    }

    private var singleEye: some View {
        ZStack {
            Ellipse()
                .fill(.white)
                .frame(width: eyeWidth, height: eyeHeight)

            Circle()
                .fill(.black)
                .frame(width: pupilSize, height: min(pupilSize, eyeHeight - 2))
                .offset(pupilOffset)
        }
        .animation(.easeInOut(duration: 0.3), value: eyeHeight)
        .animation(.easeInOut(duration: 0.5), value: pupilOffset)
    }

    private func scheduleAnimation() {
        // Cancel any pending loop by changing the ID
        animationID = UUID()
        let currentID = animationID

        switch state {
        case .idle:
            idleLoop(id: currentID)
        case .focused:
            focusedLoop(id: currentID)
        case .active:
            activeLoop(id: currentID)
        }
    }

    private func idleLoop(id: UUID) {
        guard animationID == id else { return }

        // Update immediately for first animation
        pupilOffset = CGSize(
            width: CGFloat.random(in: -5...5),
            height: CGFloat.random(in: -5...5)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            idleLoop(id: id)
        }
    }

    private func focusedLoop(id: UUID) {
        guard animationID == id else { return }

        // Update immediately for first animation
        pupilOffset = CGSize(
            width: CGFloat.random(in: -3...3),
            height: CGFloat.random(in: -2...2)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            focusedLoop(id: id)
        }
    }

    private func activeLoop(id: UUID) {
        guard animationID == id else { return }

        // Update immediately for first animation
        pupilOffset = CGSize(
            width: CGFloat.random(in: -2...2),
            height: CGFloat.random(in: -1...1)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            activeLoop(id: id)
        }
    }
}
