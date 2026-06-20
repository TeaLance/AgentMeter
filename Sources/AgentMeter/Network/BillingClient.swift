import Foundation
import AgentMeterCore

/// Networked fetch of real billed cost, to replace the local `≈$` estimate over
/// the covered range. Gated behind the `accurateCost` opt-in.
///
/// EXPERIMENTAL: the billing endpoint is not wired here yet; returns `.unavailable`
/// until implemented with verified API details. Any `URLSession` use must stay in
/// this file / `CodexQuotaClient` (see Scripts/check-offline.sh).
struct BillingClient {
    enum Result: Equatable {
        case disabled
        case unavailable
        case ok(CostEstimate)
    }

    func cost(for range: DateInterval) async -> Result {
        guard NetworkFeature.accurateCost.isEnabled else { return .disabled }
        // TODO(experimental): query the provider billing API via URLSession.
        return .unavailable
    }
}
