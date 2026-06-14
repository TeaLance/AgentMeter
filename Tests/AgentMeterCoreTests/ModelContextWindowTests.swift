import XCTest
@testable import AgentMeterCore

final class ModelContextWindowTests: XCTestCase {
    func testOneMillionTagGives1M() {
        XCTAssertEqual(contextWindow(forModelID: "claude-opus-4-8[1m]"), 1_000_000)
        XCTAssertEqual(contextWindow(forModelID: "claude-sonnet-4-6[1M]"), 1_000_000)
    }

    func testStandardModelGives200k() {
        XCTAssertEqual(contextWindow(forModelID: "claude-fable-5"), 200_000)
        XCTAssertEqual(contextWindow(forModelID: "claude-opus-4-8"), 200_000)
    }

    func testNilOrUnknownDefaultsTo200k() {
        XCTAssertEqual(contextWindow(forModelID: nil), 200_000)
        XCTAssertEqual(contextWindow(forModelID: ""), 200_000)
    }
}
