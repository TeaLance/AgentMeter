import XCTest
@testable import AgentMeterCore

final class PricingTests: XCTestCase {
    func testKnownModelCost() {
        // 1M input + 1M output on Opus 4.8 ($5 in / $25 out per MTok) = $30.
        let t = TokenBreakdown(input: 1_000_000, output: 1_000_000)
        let est = costEstimate(t, model: ModelKey(raw: "claude-opus-4-8"))
        XCTAssertEqual(est.amountUSD, 30, accuracy: 1e-6)
        XCTAssertTrue(est.isComplete)
    }

    func testCacheRatesApplied() {
        // cache read defaults to 0.1x input, cache write to 1.25x input.
        // 1M cacheRead on Opus 4.8 = 1M * (0.1 * $5) = $0.50; 1M cacheCreation = $6.25.
        let t = TokenBreakdown(cacheCreation: 1_000_000, cacheRead: 1_000_000)
        let est = costEstimate(t, model: ModelKey(raw: "claude-opus-4-8"))
        XCTAssertEqual(est.amountUSD, 6.75, accuracy: 1e-6)
    }

    func testHaikuCheaperThanOpus() {
        let t = TokenBreakdown(input: 1_000_000)
        XCTAssertEqual(costEstimate(t, model: ModelKey(raw: "claude-haiku-4-5")).amountUSD, 1, accuracy: 1e-6)
        XCTAssertEqual(costEstimate(t, model: ModelKey(raw: "claude-fable-5")).amountUSD, 10, accuracy: 1e-6)
    }

    func testUnknownModelIsIncompleteAndZero() {
        let t = TokenBreakdown(input: 1_000_000, output: 1_000_000)
        let est = costEstimate(t, model: ModelKey(raw: "gpt-5.5"))
        XCTAssertEqual(est.amountUSD, 0)
        XCTAssertFalse(est.isComplete)
    }

    func testDatedSnapshotResolvesToBasePrice() {
        let t = TokenBreakdown(input: 1_000_000)
        let est = costEstimate(t, model: ModelKey(raw: "claude-haiku-4-5-20251001"))
        XCTAssertEqual(est.amountUSD, 1, accuracy: 1e-6)
        XCTAssertTrue(est.isComplete)
    }
}
