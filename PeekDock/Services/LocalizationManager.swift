import Foundation
import Observation

@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    static let supportedLanguages: [(code: String, label: String)] = [
        ("en", "English"),
        ("ja", "日本語")
    ]

    private static let storageKey = "PeekDock.language"

    var language: String {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language, forKey: Self.storageKey)
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.storageKey),
           Self.supportedLanguages.contains(where: { $0.code == stored }) {
            self.language = stored
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.language = preferred.hasPrefix("ja") ? "ja" : "en"
        }
    }

    private var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let resolved = Bundle(path: path) else {
            return Bundle.main
        }
        return resolved
    }

    func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, value: key, comment: "")
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = NSLocalizedString(key, bundle: bundle, value: key, comment: "")
        return String(format: template, arguments: args)
    }

    var locale: Locale { Locale(identifier: language) }
}
