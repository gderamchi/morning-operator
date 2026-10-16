import Foundation

/// French follows the primary device language; every other language uses English.
public enum AppLanguage {
    private static let legacyPreferenceCleanup: Void = {
        guard let domainName = Bundle.main.bundleIdentifier else { return }
        removeLegacyLanguageOverride(in: .standard, domainName: domainName)
    }()

    public static var code: String {
        _ = legacyPreferenceCleanup
        return resolvedCode(preferredLanguages: Locale.preferredLanguages)
    }

    public static var isFrench: Bool { code == "fr" }

    /// Keep regional formats and explicit calendar/number preferences in the UI language.
    public static var locale: Locale {
        _ = legacyPreferenceCleanup
        return resolvedLocale(preferredLanguages: Locale.preferredLanguages, current: .current)
    }

    /// The locale identifier passed to deterministic composers such as the morning briefing.
    public static var localeIdentifier: String { locale.identifier }

    /// Compatibility for presentation APIs that deliberately render a pinned locale.
    /// This performs resource lookup only; the app language always follows the device.
    public static func bundle(for source: Bundle = .main, languageCode: String? = nil) -> Bundle {
        guard let path = source.path(forResource: languageCode ?? code, ofType: "lproj"),
              let localized = Bundle(path: path) else { return source }
        return localized
    }

    /// A resource's locale selects the translation; String's locale only formats values.
    public static func localized(_ value: String.LocalizationValue, table: String? = nil,
                                 bundle: Bundle = .main, comment: StaticString? = nil) -> String {
        localized(value, table: table, bundle: bundle, locale: locale, comment: comment)
    }

    static func localized(_ value: String.LocalizationValue, table: String? = nil,
                          bundle: Bundle, locale: Locale, comment: StaticString? = nil) -> String {
        String(localized: LocalizedStringResource(value, table: table, locale: locale,
                                                 bundle: .atURL(bundle.bundleURL), comment: comment))
    }

    static func resolvedCode(preferredLanguages: [String]) -> String {
        guard let primary = preferredLanguages.first else { return "en" }
        return Locale.Language(identifier: primary).languageCode?.identifier == "fr" ? "fr" : "en"
    }

    /// The previous app picker wrote this exact pair. Read only our persistent
    /// domain: launch arguments and registered defaults cannot establish its origin.
    static func removeLegacyLanguageOverride(in defaults: UserDefaults, domainName: String) {
        guard let domain = defaults.persistentDomain(forName: domainName),
              let marker = domain["more.appLanguage"] as? String,
              ["fr", "en"].contains(marker) else { return }
        if let languages = domain["AppleLanguages"] as? [String], languages == [marker] {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        // A different/unidentifiable language preference is preserved. Remove our
        // obsolete marker now so it can never identify a later iOS/user preference.
        defaults.removeObject(forKey: "more.appLanguage")
    }

    static func resolvedLocale(preferredLanguages: [String], current: Locale) -> Locale {
        let language = resolvedCode(preferredLanguages: preferredLanguages)
        guard current.language.languageCode?.identifier != language else { return current }
        var components = Locale.Components(locale: current)
        components.languageComponents.languageCode = Locale.LanguageCode(language)
        components.languageComponents.script = nil
        return Locale(components: components)
    }
}
