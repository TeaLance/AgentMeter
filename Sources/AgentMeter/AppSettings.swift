import Foundation

enum SettingsKeys {
    static let interval = "refreshIntervalSeconds"
    /// CSV of MenuBarMetric raw values shown inline in the menu bar.
    static let menuBarMetrics = "menuBarMetrics"
    static let showClaude = "showClaude"
    static let showCodex = "showCodex"
}

/// Default menu-bar selection: a single combined token figure (v1/v2 behaviour).
let defaultMenuBarMetricsCSV = MenuBarMetric.combinedTokens.rawValue

/// Refresh interval choices, in seconds.
let refreshIntervalOptions: [(label: String, seconds: Double)] = [
    ("15 秒", 15),
    ("30 秒", 30),
    ("1 分鐘", 60),
    ("5 分鐘", 300),
]
