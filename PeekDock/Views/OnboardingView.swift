import SwiftUI
import AppKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case terms
    case permission
    case tutorial
}

struct OnboardingView: View {
    @Environment(LocalizationManager.self) private var l10n
    @State private var currentStep: OnboardingStep
    @State private var hasAgreedToTerms: Bool = UserDefaults.standard.bool(forKey: "dev.kemnix.peekdock.hasAgreedToTerms")
    @State private var hasPermission: Bool = CGPreflightScreenCaptureAccess()
    @State private var needsRelaunch: Bool = false

    private let startStep: OnboardingStep
    private let onFinish: () -> Void

    private var isPermissionOnlyMode: Bool { startStep == .permission }

    init(startStep: OnboardingStep = .welcome, onFinish: @escaping () -> Void) {
        self.startStep = startStep
        self._currentStep = State(initialValue: startStep)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)

            Divider()
                .background(Color.white.opacity(0.1))

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 560, height: 420)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
        .foregroundStyle(.white)
        .task(id: currentStep) {
            guard currentStep == .permission else { return }
            let wasGrantedOnEntry = CGPreflightScreenCaptureAccess()
            hasPermission = wasGrantedOnEntry
            if !wasGrantedOnEntry {
                _ = CGRequestScreenCaptureAccess()
            }
            while !Task.isCancelled && !hasPermission {
                hasPermission = CGPreflightScreenCaptureAccess()
                if hasPermission { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if !Task.isCancelled && hasPermission && !wasGrantedOnEntry {
                needsRelaunch = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .welcome: welcomeStep
        case .terms: termsStep
        case .permission: permissionStep
        case .tutorial: tutorialStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 128, height: 128)
            Text(l10n.t("onboarding.welcome.title"))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
            Text(l10n.t("onboarding.welcome.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 8) {
                Text(l10n.t("onboarding.welcome.languageLabel"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Picker("", selection: Bindable(l10n).language) {
                    ForEach(LocalizationManager.supportedLanguages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .colorScheme(.dark)
            }
            Spacer()
        }
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("onboarding.terms.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(l10n.t("onboarding.terms.howItWorks.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))

                    VStack(alignment: .leading, spacing: 8) {
                        bulletText(l10n.t("onboarding.terms.howItWorks.storage"))
                        bulletText(l10n.t("onboarding.terms.howItWorks.bleed"))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))

                    Text(l10n.t("onboarding.terms.responsibility.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        bulletText(l10n.t("onboarding.terms.responsibility.notAffiliated"))
                        bulletText(l10n.t("onboarding.terms.responsibility.consent"))
                        bulletText(l10n.t("onboarding.terms.responsibility.compliance"))
                        bulletText(l10n.t("onboarding.terms.responsibility.asIs"))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
            .frame(maxHeight: .infinity)

            Toggle(isOn: $hasAgreedToTerms) {
                Text(l10n.t("onboarding.terms.agreeLabel"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.checkbox)
            .tint(.accentColor)
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(l10n.t("onboarding.permission.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text(l10n.t("onboarding.permission.body"))
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))

            Button(action: openPermissionSettings) {
                Text(l10n.t("onboarding.permission.openSettings"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 8) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(hasPermission ? .green : .white.opacity(0.5))
                Text(hasPermission ? l10n.t("onboarding.permission.granted") : l10n.t("onboarding.permission.waiting"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 2)

            Text(needsRelaunch
                 ? l10n.t("onboarding.permission.needsRestart")
                 : l10n.t("onboarding.permission.restartNote"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(needsRelaunch ? 0.8 : 0.5))
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var tutorialStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("onboarding.tutorial.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                tutorialRow(
                    icon: "cursorarrow.rays",
                    title: l10n.t("onboarding.tutorial.step1.title"),
                    body: l10n.t("onboarding.tutorial.step1.body")
                )
                tutorialRow(
                    icon: "video.fill",
                    title: l10n.t("onboarding.tutorial.step2.title"),
                    body: l10n.t("onboarding.tutorial.step2.body")
                )
                tutorialRow(
                    icon: "rectangle.stack.badge.plus",
                    title: l10n.t("onboarding.tutorial.step3.title"),
                    body: l10n.t("onboarding.tutorial.step3.body")
                )
                tutorialRow(
                    icon: "checklist",
                    title: l10n.t("onboarding.tutorial.step4.title"),
                    body: l10n.t("onboarding.tutorial.step4.body")
                )
                tutorialRow(
                    icon: "square.and.arrow.down",
                    title: l10n.t("onboarding.tutorial.step5.title"),
                    body: l10n.t("onboarding.tutorial.step5.body")
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func tutorialRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !isPermissionOnlyMode {
                progressDots
                Spacer()
                Button(l10n.t("button.back")) { back() }
                    .disabled(currentStep == startStep)
                    .opacity(currentStep == startStep ? 0 : 1)
            } else {
                Spacer()
            }

            Button(primaryButtonTitle) { next() }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var primaryButtonTitle: String {
        if needsRelaunch { return l10n.t("button.restartNow") }
        if isPermissionOnlyMode { return l10n.t("button.done") }
        switch currentStep {
        case .welcome: return l10n.t("button.next")
        case .terms: return l10n.t("button.agreeAndNext")
        case .permission: return l10n.t("button.next")
        case .tutorial: return l10n.t("button.getStarted")
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .terms: return hasAgreedToTerms
        case .permission: return hasPermission
        default: return true
        }
    }

    private func next() {
        if needsRelaunch {
            relaunchApp()
            return
        }
        if currentStep == .terms {
            UserDefaults.standard.set(true, forKey: "dev.kemnix.peekdock.hasAgreedToTerms")
        }
        if isPermissionOnlyMode || currentStep == .tutorial {
            onFinish()
            return
        }
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func back() {
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
        }
    }

    private func openPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func bulletText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.white.opacity(0.6))
            Text(text)
        }
    }
}
