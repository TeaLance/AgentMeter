import XCTest
@testable import AgentMeterCore

final class ModelIdentityTests: XCTestCase {
    func testStripsDateSuffix() {
        XCTAssertEqual(ModelKey(raw: "claude-haiku-4-5-20251001").id, "claude-haiku-4-5")
    }

    func testStripsBracketSuffix() {
        XCTAssertEqual(ModelKey(raw: "claude-opus-4-8[1m]").id, "claude-opus-4-8")
    }

    func testStripsBothBracketAndDate() {
        XCTAssertEqual(ModelKey(raw: "claude-haiku-4-5-20251001[1m]").id, "claude-haiku-4-5")
    }

    func testVendorClassification() {
        XCTAssertEqual(ModelKey(raw: "claude-opus-4-8").vendor, .anthropic)
        XCTAssertEqual(ModelKey(raw: "gpt-5.5").vendor, .openai)
        XCTAssertEqual(ModelKey(raw: "codex-auto-review").vendor, .openai)
        XCTAssertEqual(ModelKey(raw: "mimo-v2.5").vendor, .unknown)
    }

    func testPlainOpenAIKept() {
        XCTAssertEqual(ModelKey(raw: "gpt-5.5").id, "gpt-5.5")
    }

    func testSyntheticAndEmptyBecomeUnknown() {
        XCTAssertEqual(ModelKey(raw: "<synthetic>"), .unknown)
        XCTAssertEqual(ModelKey(raw: "   "), .unknown)
        XCTAssertEqual(ModelKey(raw: ""), .unknown)
    }

    func testEqualityByNormalizedId() {
        XCTAssertEqual(ModelKey(raw: "claude-opus-4-8[1m]"), ModelKey(raw: "claude-opus-4-8"))
    }
}
