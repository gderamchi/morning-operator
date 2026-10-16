import Foundation

public extension Error {
    /// App-owned errors supply their chosen-language explanation. Framework diagnostics
    /// can contain private paths or request data and follow the system's language.
    var moreDescription: String {
        if let localized = self as? any LocalizedError,
           let description = localized.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return String(localized: "MORE could not complete this request. Check its state before trying again.",
                      bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
    }
}
