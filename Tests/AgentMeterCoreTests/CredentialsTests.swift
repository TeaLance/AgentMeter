import XCTest
@testable import AgentMeterCore

final class CredentialsTests: XCTestCase {
    /// Build a fake JWT (`header.payload.sig`) with base64url-encoded claims.
    private func makeJWT(_ claims: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: claims)
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJ.\(b64).sig"
    }

    func testJWTDecodesPayloadClaims() {
        let token = makeJWT(["email": "x@y.com", "n": 7])
        let payload = JWT.payload(token)
        XCTAssertEqual(payload?["email"] as? String, "x@y.com")
        XCTAssertEqual(payload?["n"] as? Int, 7)
    }

    func testJWTRejectsGarbage() {
        XCTAssertNil(JWT.payload("not-a-jwt"))
        XCTAssertNil(JWT.payload(""))
    }

    func testClaudeCredentialsParse() {
        let json = """
        {"claudeAiOauth":{"emailAddress":"u@x.com","subscriptionType":"pro",
        "accessToken":"AT","refreshToken":"RT","expiresAt":1800000000000}}
        """.data(using: .utf8)!
        let c = ClaudeCredentialParser.parse(credentialsJSON: json)
        XCTAssertEqual(c?.accessToken, "AT")
        XCTAssertEqual(c?.refreshToken, "RT")
        XCTAssertEqual(c?.account.email, "u@x.com")
        XCTAssertEqual(c?.account.plan, "pro")
        XCTAssertEqual(c?.expiresAtMillis, 1_800_000_000_000)
    }

    func testClaudeEmailFallbackFromConfig() {
        let json = #"{"oauthAccount":{"emailAddress":"fallback@x.com"},"other":1}"#.data(using: .utf8)!
        XCTAssertEqual(ClaudeCredentialParser.email(fromClaudeConfigJSON: json), "fallback@x.com")
    }

    func testClaudeAccountFromConfigDerivesPlan() {
        // Real shape: token lives in the Keychain, but ~/.claude.json has the account.
        let json = #"{"oauthAccount":{"emailAddress":"a@b.com","organizationType":"claude_team"}}"#.data(using: .utf8)!
        let a = ClaudeCredentialParser.account(fromClaudeConfigJSON: json)
        XCTAssertEqual(a?.email, "a@b.com")
        XCTAssertEqual(a?.plan, "team")
    }

    func testCodexCredentialsParseDecodesIdToken() {
        let idToken = makeJWT([
            "email": "c@x.com",
            "https://api.openai.com/auth": ["chatgpt_plan_type": "plus"],
        ])
        let json = """
        {"tokens":{"access_token":"CAT","refresh_token":"CRT","id_token":"\(idToken)","account_id":"acc-1"}}
        """.data(using: .utf8)!
        let c = CodexCredentialParser.parse(authJSON: json)
        XCTAssertEqual(c?.accessToken, "CAT")
        XCTAssertEqual(c?.accountId, "acc-1")
        XCTAssertEqual(c?.account.email, "c@x.com")
        XCTAssertEqual(c?.account.plan, "plus")
    }

    func testExpiryFromMillis() {
        let future = ClaudeCredentials(accessToken: "a", refreshToken: nil,
                                       expiresAtMillis: 2_000_000_000_000, account: .init())
        XCTAssertFalse(future.isExpired(now: Date(timeIntervalSince1970: 1_000_000_000)))
        let past = ClaudeCredentials(accessToken: "a", refreshToken: nil,
                                     expiresAtMillis: 1_000_000, account: .init())
        XCTAssertTrue(past.isExpired(now: Date(timeIntervalSince1970: 1_000_000_000)))
    }
}
