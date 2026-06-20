import Foundation

/// Logged-in account identity for a service — decoded entirely from local files
/// (no network). Used to show "who's logged in" and the plan tier.
public struct ServiceAccount: Equatable, Sendable {
    public var email: String?
    public var plan: String?
    public init(email: String? = nil, plan: String? = nil) {
        self.email = email
        self.plan = plan
    }
    public var isEmpty: Bool { email == nil && plan == nil }
    public var nonEmpty: ServiceAccount? { isEmpty ? nil : self }
}

/// Local JWT payload decode (no signature validation) — the id_token's middle
/// segment is base64url-encoded JSON.
public enum JWT {
    public static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}

// MARK: - Claude

/// Parsed from `~/.claude/.credentials.json`. The access token is what the
/// networked quota client would send as a Bearer header (network is opt-in).
public struct ClaudeCredentials: Equatable, Sendable {
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAtMillis: Double?
    public var account: ServiceAccount

    public init(accessToken: String?, refreshToken: String?,
                expiresAtMillis: Double?, account: ServiceAccount) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMillis = expiresAtMillis
        self.account = account
    }

    public func isExpired(now: Date = Date(), skew: TimeInterval = 30) -> Bool {
        guard let ms = expiresAtMillis else { return false }
        return now.timeIntervalSince1970 + skew >= ms / 1000
    }
}

public enum ClaudeCredentialParser {
    public static func parse(credentialsJSON: Data) -> ClaudeCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: credentialsJSON) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        return ClaudeCredentials(
            accessToken: oauth["accessToken"] as? String,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAtMillis: (oauth["expiresAt"] as? NSNumber)?.doubleValue,
            account: ServiceAccount(email: oauth["emailAddress"] as? String,
                                    plan: oauth["subscriptionType"] as? String))
    }

    /// Email fallback from `~/.claude.json` → `oauthAccount.emailAddress`.
    public static func email(fromClaudeConfigJSON data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = root["oauthAccount"] as? [String: Any] else { return nil }
        return acct["emailAddress"] as? String
    }

    /// Account (email + plan) from `~/.claude.json`. This file is present even when
    /// the token lives in the Keychain, so it's how we show the Claude account
    /// without reading the Keychain. Plan is derived from `organizationType`
    /// (e.g. "claude_team" → "team").
    public static func account(fromClaudeConfigJSON data: Data) -> ServiceAccount? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = root["oauthAccount"] as? [String: Any] else { return nil }
        var plan = acct["organizationType"] as? String
        if let p = plan, p.hasPrefix("claude_") { plan = String(p.dropFirst("claude_".count)) }
        return ServiceAccount(email: acct["emailAddress"] as? String, plan: plan).nonEmpty
    }
}

// MARK: - Codex

/// Parsed from `~/.codex/auth.json`. Account identity is decoded from the
/// id_token JWT locally.
public struct CodexCredentials: Equatable, Sendable {
    public var accessToken: String?
    public var refreshToken: String?
    public var idToken: String?
    public var accountId: String?
    public var account: ServiceAccount

    public init(accessToken: String?, refreshToken: String?, idToken: String?,
                accountId: String?, account: ServiceAccount) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountId = accountId
        self.account = account
    }
}

// MARK: - File reader (local only — never the Keychain)

/// Reads credential FILES from disk (no Keychain access, preserving that
/// privacy promise). Only invoked when the user opted into account display or a
/// networked feature.
public struct CredentialReader {
    private let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public func claude() -> ClaudeCredentials? {
        // The token may be in ~/.claude/.credentials.json (older setups) — read it
        // if present. macOS keeps it in the Keychain instead, which we never read;
        // the account (email/plan) then comes from ~/.claude.json below.
        let credsURL = home.appendingPathComponent(".claude/.credentials.json")
        var creds = (try? Data(contentsOf: credsURL)).flatMap(ClaudeCredentialParser.parse(credentialsJSON:))

        if let cfg = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
           let acct = ClaudeCredentialParser.account(fromClaudeConfigJSON: cfg) {
            if creds == nil {
                creds = ClaudeCredentials(accessToken: nil, refreshToken: nil,
                                          expiresAtMillis: nil, account: acct)
            } else {
                if creds!.account.email == nil { creds!.account.email = acct.email }
                if creds!.account.plan == nil { creds!.account.plan = acct.plan }
            }
        }
        return creds
    }

    public func codex() -> CodexCredentials? {
        let url = home.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return CodexCredentialParser.parse(authJSON: data)
    }
}

public enum CodexCredentialParser {
    public static func parse(authJSON: Data) -> CodexCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: authJSON) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else { return nil }
        let idToken = tokens["id_token"] as? String
        return CodexCredentials(
            accessToken: tokens["access_token"] as? String,
            refreshToken: tokens["refresh_token"] as? String,
            idToken: idToken,
            accountId: tokens["account_id"] as? String,
            account: idToken.flatMap(account(fromIDToken:)) ?? ServiceAccount())
    }

    private static func account(fromIDToken token: String) -> ServiceAccount {
        guard let claims = JWT.payload(token) else { return ServiceAccount() }
        let email = claims["email"] as? String
        // Plan may be a namespaced nested object or a flat claim.
        var plan = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_plan_type"] as? String
        plan = plan ?? claims["chatgpt_plan_type"] as? String
        return ServiceAccount(email: email, plan: plan)
    }
}
