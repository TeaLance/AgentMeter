import XCTest
@testable import AgentMeterCore

final class ContextWindowTests: XCTestCase {
    func testFractionIsUsedOverTotal() {
        XCTAssertEqual(ContextWindow(used: 60_000, total: 1_000_000).fraction, 0.06, accuracy: 1e-9)
    }

    func testFractionClampsToOne() {
        XCTAssertEqual(ContextWindow(used: 250_000, total: 200_000).fraction, 1.0, accuracy: 1e-9)
    }

    func testFractionZeroWhenTotalNonPositive() {
        XCTAssertEqual(ContextWindow(used: 100, total: 0).fraction, 0.0, accuracy: 1e-9)
    }
}
