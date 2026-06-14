import XCTest
@testable import AgentMeterCore

final class TokenBreakdownTests: XCTestCase {
    func testTotalSumsAllComponents() {
        let b = TokenBreakdown(input: 10, output: 5, cacheCreation: 3, cacheRead: 2, reasoning: 1)
        XCTAssertEqual(b.total, 21)
    }

    func testBillableTotalExcludesCacheReads() {
        let b = TokenBreakdown(input: 10, output: 5, cacheCreation: 3, cacheRead: 1000, reasoning: 2)
        XCTAssertEqual(b.billableTotal, 20)
    }

    func testAdditionIsComponentwise() {
        let a = TokenBreakdown(input: 1, output: 2, cacheCreation: 3, cacheRead: 4, reasoning: 5)
        let b = TokenBreakdown(input: 10, output: 20, cacheCreation: 30, cacheRead: 40, reasoning: 50)
        XCTAssertEqual(a + b, TokenBreakdown(input: 11, output: 22, cacheCreation: 33, cacheRead: 44, reasoning: 55))
    }
}
