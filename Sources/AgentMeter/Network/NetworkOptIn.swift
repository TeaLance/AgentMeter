import Foundation

/// Opt-in features that read sensitive local credentials and/or touch the network.
/// AgentMeter is fully offline by default; each feature here is OFF until the user
/// confirms a dialog. ALL code that touches the network lives under
/// `Sources/AgentMeter/Network/` — enforced by `Scripts/check-offline.sh` (CI) so
/// the offline-by-default guarantee stays verifiable.
enum NetworkFeature: String, CaseIterable, Identifiable {
    /// Real Codex 5h / weekly quota — reads ~/.codex credentials and contacts OpenAI.
    case codexQuota
    /// Show the logged-in account (email / plan). Reads local credential FILES only
    /// (never the Keychain); NOT a network call, but gated behind the same
    /// confirmation because it reads sensitive files.
    case showAccounts
    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .codexQuota:   return SettingsKeys.netCodexQuota
        case .showAccounts: return SettingsKeys.showAccounts
        }
    }

    /// Whether the feature actually touches the network (vs. only reading files).
    var usesNetwork: Bool { self == .codexQuota }

    /// Uses the global `tr` (nonisolated); views observing `LanguageStore` re-render.
    var title: String {
        switch self {
        case .codexQuota:   return tr("Codex live quota", "Codex 即時額度")
        case .showAccounts: return tr("Show logged-in accounts", "顯示登入帳號")
        }
    }

    /// Shown inside the confirmation dialog before the feature is enabled.
    var explanation: String {
        switch self {
        case .codexQuota:
            return tr("Reads local ~/.codex credentials and contacts OpenAI to fetch your 5-hour / weekly quota. AgentMeter is otherwise fully offline and only connects while this is on.",
                      "會讀取本機 ~/.codex 憑證並連線 OpenAI 取得 5 小時／每週額度。AgentMeter 平常完全離線，僅在此功能開啟時連線。")
        case .showAccounts:
            return tr("Reads your local Claude/Codex login credential files (not the Keychain) to show which account is signed in and its plan. Stays fully offline — no network.",
                      "會讀取本機 Claude/Codex 登入憑證檔(不讀 Keychain)以顯示登入的帳號與方案。完全離線、不連網。")
        }
    }

    /// Default ON (for accurate quota / account display): absent key reads as true.
    var isEnabled: Bool { (UserDefaults.standard.object(forKey: defaultsKey) as? Bool) ?? true }
}
