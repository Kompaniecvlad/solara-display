import Foundation

/// Language the menu, HUD, and alerts use. Short badges are what the switcher shows.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case es
    case ru
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var badge: String {
        switch self {
        case .en: "EN"
        case .es: "ES"
        case .ru: "RU"
        case .zhHans: "CH"
        }
    }

    var accessibilityName: String {
        switch self {
        case .en: "English"
        case .es: "Español"
        case .ru: "Русский"
        case .zhHans: "中文"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }

    static let storageKey = "solara.language"

    /// Saved choice, or the system language when the user has not picked one yet.
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        return matchedToSystem
    }

    private static var matchedToSystem: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ru") { return .ru }
        if preferred.hasPrefix("es") { return .es }
        if preferred.hasPrefix("zh") { return .zhHans }
        return .en
    }
}
