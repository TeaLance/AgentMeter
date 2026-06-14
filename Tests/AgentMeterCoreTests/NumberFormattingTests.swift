import XCTest
@testable import AgentMeterCore

final class NumberFormattingTests: XCTestCase {
    func testCompactTokenString() {
        XCTAssertEqual(0.compactTokenString, "0")
        XCTAssertEqual(42.compactTokenString, "42")
        XCTAssertEqual(999.compactTokenString, "999")
        XCTAssertEqual(1234.compactTokenString, "1.2K")
        XCTAssertEqual(12345.compactTokenString, "12.3K")
        XCTAssertEqual(1_500_000.compactTokenString, "1.5M")
        XCTAssertEqual(2_000_000_000.compactTokenString, "2.0B")
    }
}
