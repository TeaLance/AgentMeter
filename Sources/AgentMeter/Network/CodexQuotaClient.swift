import Foundation
import AgentMeterCore

/// Networked fetch of Codex's real 5-hour / weekly quota. Gated behind the
/// `codexQuota` opt-in — it MUST refuse to run unless the user enabled it, so a
/// code-path bug can't make an unconsented request.
///
/// EXPERIMENTAL: the OpenAI quota endpoint + credential exchange are not wired
/// here yet (they require verified, undocumented API details). Until then this
/// reports `.unavailable` rather than fabricating numbers. When implemented, the
/// `URLSession` call belongs in this file (and only this file / `BillingClient`),
/// keeping the offline-by-default guarantee verifiable via Scripts/check-offline.sh.
struct CodexQuotaClient {
    enum Result: Equatable {
        case disabled       // user hasn't opted in
        case unavailable    // opted in, but not implemented / no credentials / network error
        case ok(fiveHour: QuotaWindow, weekly: QuotaWindow)
    }

    func fetch() async -> Result {
        guard NetworkFeature.codexQuota.isEnabled else { return .disabled }
        // TODO(experimental): read ~/.codex credentials and query OpenAI here via
        // URLSession, mapping the response into QuotaWindow values. Returns
        // .unavailable until wired with verified endpoint details.
        return .unavailable
    }
}
