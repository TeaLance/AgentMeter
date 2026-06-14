import Foundation

enum SettingsKeys {
    static let interval = "refreshIntervalSeconds"
    static let labelMode = "menuBarLabelMode"
    static let showClaude = "showClaude"
    static let showCodex = "showCodex"
}

/// What the menu-bar text shows.
enum MenuBarLabelMode: String, CaseIterable, Identifiable {
    case combined
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: return "合計 (Claude + Codex)"
        case .claude:   return "只 Claude Code"
        case .codex:    return "只 Codex"
        }
    }
}

/// Refresh interval choices, in seconds.
let refreshIntervalOptions: [(label: String, seconds: Double)] = [
    ("15 秒", 15),
    ("30 秒", 30),
    ("1 分鐘", 60),
    ("5 分鐘", 300),
]
