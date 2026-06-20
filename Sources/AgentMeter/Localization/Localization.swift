import Foundation
import Combine

/// UI language. Manual choice only (no follow-system), per product decision.
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh   // 繁體中文
    case en   // English
    var id: String { rawValue }
    var displayName: String { self == .zh ? "繁體中文" : "English" }
}

/// Drives live language switching. Views observe this; toggling re-renders the
/// whole tree without a restart. Non-View code reads the static snapshot.
@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    static let key = "appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            _currentLanguage = language
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init)
        let lang = stored ?? .zh
        self.language = lang
        _currentLanguage = lang
    }

    /// View-facing translate that participates in SwiftUI dependency tracking.
    func tr(_ en: String, _ zh: String) -> String { language == .zh ? zh : en }
}

/// Snapshot for non-View callers (formatters, `MenuBarMetric`). Written on the
/// main actor by `LanguageStore`; read anywhere.
var _currentLanguage: AppLanguage = .zh

/// Global translate for non-View code. Views should prefer `languageStore.tr(...)`
/// so changes re-render immediately.
func tr(_ en: String, _ zh: String) -> String {
    _currentLanguage == .zh ? zh : en
}
