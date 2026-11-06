import Foundation
import Observation

enum AppLanguage: String, CaseIterable {
    case system, chinese, english
}

/// UI language. Defaults to the system language; can be pinned from the settings menu.
/// Observable, so SwiftUI views redraw as soon as it changes (no relaunch).
@Observable
final class Language {
    static let shared = Language()
    private static let key = "language"

    private(set) var setting: AppLanguage

    private init() {
        setting = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
    }

    func set(_ language: AppLanguage, persist: Bool = true) {
        setting = language
        if persist { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    var isChinese: Bool {
        switch setting {
        case .chinese: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }
}

/// The string for the current UI language. Pairs live next to where they're used.
func L(_ chinese: String, _ english: String) -> String {
    Language.shared.isChinese ? chinese : english
}
