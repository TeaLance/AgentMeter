import XCTest
@testable import AgentMeterCore

final class HexColorTests: XCTestCase {
    func testParsesSixDigitWithHash() {
        let c = HexColor.rgb("#D97757")
        XCTAssertEqual(c?.r, 217)
        XCTAssertEqual(c?.g, 119)
        XCTAssertEqual(c?.b, 87)
    }

    func testParsesWithoutHashAndLowercase() {
        let c = HexColor.rgb("6c6c70")
        XCTAssertEqual(c?.r, 108)
        XCTAssertEqual(c?.g, 108)
        XCTAssertEqual(c?.b, 112)
    }

    func testRejectsInvalid() {
        XCTAssertNil(HexColor.rgb("nope"))
        XCTAssertNil(HexColor.rgb("#12345"))   // wrong length
        XCTAssertNil(HexColor.rgb(""))
    }

    func testFormatsUppercaseWithHash() {
        XCTAssertEqual(HexColor.string(r: 217, g: 119, b: 87), "#D97757")
    }

    func testFormatClampsOutOfRange() {
        XCTAssertEqual(HexColor.string(r: 300, g: -5, b: 0), "#FF0000")
    }

    func testRoundTrip() {
        for hex in ["#D97757", "#6C6C70", "#000000", "#FFFFFF"] {
            let c = HexColor.rgb(hex)!
            XCTAssertEqual(HexColor.string(r: c.r, g: c.g, b: c.b), hex)
        }
    }
}
