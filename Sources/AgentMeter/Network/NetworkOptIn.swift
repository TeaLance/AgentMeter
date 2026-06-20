import Foundation

/// Opt-in network features. AgentMeter is fully offline by default; each feature
/// here is OFF until the user confirms a "this needs internet" dialog. ALL code
/// that touches the network lives under `Sources/AgentMeter/Network/` — enforced
/// by `Scripts/check-offline.sh` (run in CI) so the offline-by-default guarantee
/// stays verifiable.
enum NetworkFeature: String, CaseIterable, Identifiable {
    case codexQuota
    case accurateCost
    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .codexQuota:   return SettingsKeys.netCodexQuota
        case .accurateCost: return SettingsKeys.netAccurateCost
        }
    }

    /// Uses the global `tr` (nonisolated); views observing `LanguageStore` re-render.
    var title: String {
        switch self {
        case .codexQuota:   return tr("Codex live quota", "Codex 即時額度")
        case .accurateCost: return tr("Accurate cost", "精準花費")
        }
    }

    /// Shown inside the confirmation dialog before the feature is enabled.
    var explanation: String {
        switch self {
        case .codexQuota:
            return tr("Reads local ~/.codex credentials and contacts OpenAI to fetch your 5-hour / weekly quota. AgentMeter is otherwise fully offline and only connects while this is on.",
                      "會讀取本機 ~/.codex 憑證並連線 OpenAI 取得 5 小時／每週額度。AgentMeter 平常完全離線，僅在此功能開啟時連線。")
        case .accurateCost:
            return tr("Contacts the provider's billing API to replace the local estimate with real spend. AgentMeter is otherwise fully offline and only connects while this is on.",
                      "會連線供應商帳單 API，用真實花費取代本機估算。AgentMeter 平常完全離線，僅在此功能開啟時連線。")
        }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
}
