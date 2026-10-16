import Foundation
import Observation
import Synchronization

/// One choice for the interface, local models, recognition, speech and formatting.
public enum AppLanguage {
    public static let preferenceKey = "more.appLanguage"
    public static let supportedCodes = ["fr", "en"]
    private static let preference = LanguagePreference()

    public static var code: String { preference.code }
    public static var isFrench: Bool { code == "fr" }

    /// Resolve the first system language only; unsupported languages start in French.
    public static func resolve(saved: String?, preferredLanguages: [String]) -> String {
        if let saved, supportedCodes.contains(saved) { return saved }
        let system = preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        return system == "en" ? "en" : "fr"
    }

    public static func initialize() { setChosenLanguage(code) }

    public static func setChosenLanguage(_ code: String) {
        guard supportedCodes.contains(code) else { return }
        preference.code = code
        UserDefaults.standard.set(code, forKey: preferenceKey)
        // iOS owns permission sheets and Siri metadata; its bundle choice updates
        // on the next launch. Provider web pages keep their own language settings.
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }

    public static var locale: Locale {
        let current = Locale.current
        return current.language.languageCode?.identifier == code
            ? current : Locale(identifier: code == "fr" ? "fr_FR" : "en_US")
    }
    public static var localeIdentifier: String { locale.identifier }

    /// Foundation strings need an explicit language bundle for an immediate switch;
    /// setting SwiftUI's environment locale alone does not change Bundle.module.
    public static func bundle(for source: Bundle = .main, languageCode: String? = nil) -> Bundle {
        guard let path = source.path(forResource: languageCode ?? code, ofType: "lproj"),
              let localized = Bundle(path: path) else { return source }
        return localized
    }
}

/// Observable reads also update prose built with AppLanguage.isFrench in SwiftUI.
/// Recognition and local model tasks may read the same preference off the main actor.
private final class LanguagePreference: Observable, @unchecked Sendable {
    private let registrar = ObservationRegistrar()
    private let value = Mutex(AppLanguage.resolve(saved: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey),
                                                  preferredLanguages: Locale.preferredLanguages))
    var code: String {
        get {
            registrar.access(self, keyPath: \.code)
            return value.withLock { $0 }
        }
        set {
            registrar.withMutation(of: self, keyPath: \.code) { value.withLock { $0 = newValue } }
        }
    }
}
