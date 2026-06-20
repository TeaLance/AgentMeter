import Foundation

enum SettingsKeys {
    static let interval = "refreshIntervalSeconds"
    /// CSV of MenuBarMetric raw values shown inline in the menu bar.
    static let menuBarMetrics = "menuBarMetrics"
    static let showClaude = "showClaude"
    static let showCodex = "showCodex"
    /// Which quota the Claude panel shows as its hero number (`ClaudeHero`).
    static let heroMetricClaude = "heroMetricClaude"
    // Floating desktop HUD.
    static let floatingEnabled = "floatingEnabled"
    static let floatingShowClaude = "floatingShowClaude"
    static let floatingShowCodex = "floatingShowCodex"
    static let floatingIdleOpacity = "floatingIdleOpacity"
    // Opt-in (default OFF; each gated behind a confirmation).
    static let netCodexQuota = "netCodexQuota"     // networked Codex quota
    static let showAccounts = "showAccounts"        // read credential files to show account
}

/// The Claude panel's primary "hero" metric. Default 5-hour; the panel's
/// `[5h｜週]` toggle and Settings can switch it to weekly.
enum ClaudeHero: String { case fiveHour, weekly }

/// Default menu-bar selection: a single combined token figure (v1/v2 behaviour).
let defaultMenuBarMetricsCSV = MenuBarMetric.combinedTokens.rawValue

/// Refresh interval choices, in seconds.
let refreshIntervalSecondsOptions: [Double] = [15, 30, 60, 300]

/// Localized label for a refresh interval (re-evaluated on language change).
func refreshIntervalLabel(_ seconds: Double) -> String {
    switch seconds {
    case 15:  return tr("15 sec", "15 秒")
    case 30:  return tr("30 sec", "30 秒")
    case 60:  return tr("1 min", "1 分鐘")
    default:  return tr("5 min", "5 分鐘")
    }
}
