import Foundation

/// Refreshes the Codex OAuth access token and writes the new tokens back to
/// ~/.codex/auth.json. Endpoint + client_id are from the cc-bar reference (MIT).
/// Networking lives only here and in CodexQuotaClient (see Scripts/check-offline.sh).
struct CodexTokenRefresher {
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let authFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")

    /// Exchange the refresh token for a fresh access (and id) token; persist + return it.
    func refresh(refreshToken: String) async -> String? {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ["grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": clientID,
                    "scope": "openid profile email"]
        req.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { return nil }
        persist(access: access,
                refresh: json["refresh_token"] as? String ?? refreshToken,
                idToken: json["id_token"] as? String)
        return access
    }

    /// Merge new tokens into the existing auth.json (preserving other fields).
    private func persist(access: String, refresh: String, idToken: String?) {
        guard let data = try? Data(contentsOf: authFile),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var tokens = root["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = access
        tokens["refresh_token"] = refresh
        if let idToken { tokens["id_token"] = idToken }
        root["tokens"] = tokens
        if let out = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted) {
            try? out.write(to: authFile)
        }
    }
}
