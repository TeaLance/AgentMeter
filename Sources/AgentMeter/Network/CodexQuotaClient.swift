import Foundation
import AgentMeterCore

/// Fetches Codex's real 5-hour / weekly quota. Gated behind the `codexQuota`
/// opt-in — refuses to run unless the user enabled it.
///
/// Endpoint + auth are from the cc-bar reference (MIT): `GET wham/usage` with a
/// Bearer access token (refreshed on 401). The response field names aren't
/// publicly documented, so parsing is defensive and falls back to `.unavailable`
/// rather than guessing.
struct CodexQuotaClient {
    enum Result: Equatable {
        case disabled       // not opted in
        case unavailable    // no credentials / network or parse failure
        case ok(fiveHour: QuotaWindow, weekly: QuotaWindow?)
    }

    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    func fetch(reader: CredentialReader = CredentialReader()) async -> Result {
        guard NetworkFeature.codexQuota.isEnabled else { return .disabled }
        guard let creds = reader.codex(), let token = creds.accessToken else { return .unavailable }

        if let result = await request(token: token, accountId: creds.accountId) { return result }
        // 401 / failure → try one refresh, then retry once.
        if let refresh = creds.refreshToken,
           let fresh = await CodexTokenRefresher().refresh(refreshToken: refresh),
           let retried = await request(token: fresh, accountId: creds.accountId) {
            return retried
        }
        return .unavailable
    }

    private func request(token: String, accountId: String?) async -> Result? {
        var req = URLRequest(url: usageURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId { req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200 else { return nil }   // 401 → caller refreshes
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rate = json["rate_limit"] as? [String: Any],
              let primary = window(rate["primary_window"]) else { return .unavailable }
        return .ok(fiveHour: primary, weekly: window(rate["secondary_window"]))
    }

    /// Map a window object to QuotaWindow, tolerating a few field-name variants.
    private func window(_ any: Any?) -> QuotaWindow? {
        guard let w = any as? [String: Any] else { return nil }
        let used = (w["used_percent"] ?? w["usage_percent"] ?? w["used"]) as? NSNumber
        guard let usedPercent = used?.doubleValue else { return nil }
        var resetsAt: Date?
        if let secs = (w["resets_in_seconds"] ?? w["reset_after_seconds"]) as? NSNumber {
            resetsAt = Date().addingTimeInterval(secs.doubleValue)
        } else if let epoch = (w["resets_at"] ?? w["reset_at"]) as? NSNumber {
            resetsAt = Date(timeIntervalSince1970: epoch.doubleValue)
        }
        return QuotaWindow(usedPercent: usedPercent, resetsAt: resetsAt)
    }
}
