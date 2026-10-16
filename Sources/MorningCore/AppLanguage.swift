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

    /// A saved choice wins; first launch follows French primary language or English otherwise.
    public static func resolve(saved: String?, preferredLanguages: [String]) -> String {
        if let saved, supportedCodes.contains(saved) { return saved }
        return resolvedCode(preferredLanguages: preferredLanguages)
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

    /// Keep regional formats and explicit calendar/number preferences in the selected language.
    public static var locale: Locale {
        resolvedLocale(saved: code, preferredLanguages: Locale.preferredLanguages, current: .current)
    }
    public static var localeIdentifier: String { locale.identifier }

    /// Foundation strings need an explicit language bundle for an immediate switch;
    /// setting SwiftUI's environment locale alone does not change Bundle.module.
    public static func bundle(for source: Bundle = .main, languageCode: String? = nil) -> Bundle {
        guard let path = source.path(forResource: languageCode ?? code, ofType: "lproj"),
              let localized = Bundle(path: path) else { return source }
        return localized
    }

    public static func localized(_ value: String.LocalizationValue, table: String? = nil,
                                 bundle: Bundle = .main, comment: StaticString? = nil) -> String {
        localized(value, table: table, bundle: bundle, locale: locale, comment: comment)
    }

    /// Explicit locale supports deterministic composers and extension-owned snapshots.
    public static func localized(_ value: String.LocalizationValue, table: String? = nil,
                                 bundle: Bundle = .main, locale: Locale, comment: StaticString? = nil) -> String {
        let selectedBundle = self.bundle(for: bundle, languageCode: locale.language.languageCode?.identifier)
        return String(localized: LocalizedStringResource(value, table: table, locale: locale,
            bundle: .atURL(selectedBundle.bundleURL), comment: comment))
    }

    static func resolvedCode(preferredLanguages: [String]) -> String {
        guard let primary = preferredLanguages.first else { return "en" }
        return Locale.Language(identifier: primary).languageCode?.identifier == "fr" ? "fr" : "en"
    }

    static func resolvedLocale(saved: String? = nil, preferredLanguages: [String], current: Locale) -> Locale {
        let language = resolve(saved: saved, preferredLanguages: preferredLanguages)
        guard current.language.languageCode?.identifier != language else { return current }
        var components = Locale.Components(locale: current)
        components.languageComponents.languageCode = Locale.LanguageCode(language)
        components.languageComponents.script = nil
        return Locale(components: components)
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
