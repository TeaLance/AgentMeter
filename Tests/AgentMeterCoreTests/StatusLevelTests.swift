import XCTest
@testable import AgentMeterCore

final class StatusLevelTests: XCTestCase {
    // Status is driven by how much quota REMAINS (remaining = 100 - used):
    //   remaining >= 50           -> normal   (used <= 50)
    //   25 <= remaining < 50      -> warning  (50 < used <= 75)
    //   10 <= remaining < 25      -> low      (75 < used <= 90)
    //   remaining < 10            -> empty    (used > 90)

    func testNormalWhenPlentyRemains() {
        XCTAssertEqual(StatusLevel.forUsed(percent: 0), .normal)
        XCTAssertEqual(StatusLevel.forUsed(percent: 29), .normal)
        XCTAssertEqual(StatusLevel.forUsed(percent: 50), .normal)
    }

    func testWarningBand() {
        XCTAssertEqual(StatusLevel.forUsed(percent: 50.1), .warning)
        XCTAssertEqual(StatusLevel.forUsed(percent: 64), .warning)
        XCTAssertEqual(StatusLevel.forUsed(percent: 75), .warning)
    }

    func testLowBand() {
        XCTAssertEqual(StatusLevel.forUsed(percent: 75.1), .low)
        XCTAssertEqual(StatusLevel.forUsed(percent: 88), .low)
        XCTAssertEqual(StatusLevel.forUsed(percent: 90), .low)
    }

    func testEmptyWhenNearlyExhausted() {
        XCTAssertEqual(StatusLevel.forUsed(percent: 90.1), .empty)
        XCTAssertEqual(StatusLevel.forUsed(percent: 100), .empty)
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(StatusLevel.forUsed(percent: -10), .normal)
        XCTAssertEqual(StatusLevel.forUsed(percent: 150), .empty)
    }
}
