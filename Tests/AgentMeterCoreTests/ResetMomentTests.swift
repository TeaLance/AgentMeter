import XCTest
@testable import AgentMeterCore

final class ResetMomentTests: XCTestCase {
    // now = Thursday 2026-11-19 22:00 Taipei (UTC+8) == 14:00 UTC
    private let now = utc(2026, 11, 19, 14)

    private func zh(_ d: Date?, now: Date? = nil, calendar: Calendar = taipeiCalendar) -> String? {
        ResetMoment.text(for: d, now: now ?? self.now, calendar: calendar, language: .zh)
    }
    private func en(_ d: Date?) -> String? {
        ResetMoment.text(for: d, now: now, calendar: taipeiCalendar, language: .en)
    }

    func testToday() {
        XCTAssertEqual(zh(utc(2026, 11, 19, 15)), "今天 23:00")
        XCTAssertEqual(en(utc(2026, 11, 19, 15)), "today 23:00")
    }

    func testTomorrowIsACalendarDayNotA24HourSpan() {
        XCTAssertEqual(zh(utc(2026, 11, 20, 1)), "明天 09:00")          // 11 h away
        XCTAssertEqual(zh(utc(2026, 11, 20, 15, 30)), "明天 23:30")     // 25.5 h away, still Friday
        XCTAssertEqual(en(utc(2026, 11, 20, 1)), "tomorrow 09:00")
    }

    func testWeekdayFromTwoToSixDaysOut() {
        XCTAssertEqual(zh(utc(2026, 11, 21, 2)), "星期六 10:00")
        XCTAssertEqual(en(utc(2026, 11, 21, 2)), "Sat 10:00")
        XCTAssertEqual(zh(utc(2026, 11, 22, 4, 5)), "星期日 12:05")
        XCTAssertEqual(zh(utc(2026, 11, 25, 15)), "星期三 23:00")       // 6 days out
    }

    func testSameWeekdayNextWeekIsMarkedNext() {
        // A weekly window that just reset: next reset is next Thursday, not "today".
        XCTAssertEqual(zh(utc(2026, 11, 26, 13)), "下星期四 21:00")
        XCTAssertEqual(en(utc(2026, 11, 26, 13)), "next Thu 21:00")
    }

    func testBeyondAWeekShowsDate() {
        XCTAssertEqual(zh(utc(2026, 11, 27, 0)), "11/27 08:00")
        XCTAssertEqual(en(utc(2026, 11, 27, 0)), "11/27 08:00")
    }

    func testRoundsToNearestMinute() {
        XCTAssertEqual(zh(utc(2026, 11, 19, 14, 59, 47)), "今天 23:00")
        XCTAssertEqual(zh(utc(2026, 11, 19, 15, 0, 29)), "今天 23:00")
        // 23:59:40 rounds to midnight, which reads as the end of today.
        XCTAssertEqual(zh(utc(2026, 11, 19, 15, 59, 40)), "今天 24:00")
    }

    func testMidnightReadsAs2400OfThePreviousDay() {
        // Midnight is the end of the day before, so "明天 00:00" (Fri 00:00)
        // reads as "今天 24:00" — tonight, not tomorrow.
        XCTAssertEqual(zh(utc(2026, 11, 19, 16)), "今天 24:00")          // Fri 11/20 00:00
        XCTAssertEqual(en(utc(2026, 11, 19, 16)), "today 24:00")
        XCTAssertEqual(zh(utc(2026, 11, 20, 16)), "明天 24:00")          // Sat 11/21 00:00
        XCTAssertEqual(en(utc(2026, 11, 20, 16)), "tomorrow 24:00")
        XCTAssertEqual(zh(utc(2026, 11, 21, 16)), "星期六 24:00")        // Sun 11/22 00:00
        XCTAssertEqual(en(utc(2026, 11, 21, 16)), "Sat 24:00")
        XCTAssertEqual(zh(utc(2026, 11, 26, 16)), "下星期四 24:00")      // Fri 11/27 00:00
        XCTAssertEqual(zh(utc(2026, 11, 27, 16)), "11/27 24:00")         // Sat 11/28 00:00
        // One minute past midnight is still the new day.
        XCTAssertEqual(zh(utc(2026, 11, 19, 16, 1)), "明天 00:01")
    }

    func testMidnightThatHasJustStartedStaysToday0000() {
        // now = Fri 00:00:10; a reset 10 s later rounds to Fri 00:00, which is
        // the start of today — "今天 24:00" would point a whole day ahead.
        XCTAssertEqual(zh(utc(2026, 11, 19, 16, 0, 20), now: utc(2026, 11, 19, 16, 0, 10)), "今天 00:00")
    }

    func testNonGregorianSystemCalendarStillShowsGregorianDate() {
        for id in [Calendar.Identifier.chinese, .republicOfChina, .islamicUmmAlQura, .hebrew] {
            var cal = Calendar(identifier: id)
            cal.timeZone = taipei
            XCTAssertEqual(zh(utc(2026, 11, 27, 0), calendar: cal), "11/27 08:00", "\(id)")
            XCTAssertEqual(zh(utc(2026, 11, 21, 2), calendar: cal), "星期六 10:00", "\(id)")
            XCTAssertEqual(zh(utc(2026, 11, 20, 1), calendar: cal), "明天 09:00", "\(id)")
        }
    }

    func testNilOrPastGivesNil() {
        XCTAssertNil(zh(nil))
        XCTAssertNil(zh(now))
        XCTAssertNil(zh(utc(2026, 11, 19, 13)))
    }

    func testDayBoundariesFollowCalendarTimeZoneAcrossDST() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // Sat 2026-10-31 22:00 EDT (UTC-4); DST ends Sun 2026-11-01 02:00.
        let nyNow = utc(2026, 11, 1, 2)
        XCTAssertEqual(zh(utc(2026, 11, 2, 4), now: nyNow, calendar: ny), "明天 23:00")      // Sun 23:00 EST
        XCTAssertEqual(zh(utc(2026, 11, 2, 5, 30), now: nyNow, calendar: ny), "星期一 00:30") // Mon 00:30 EST
        // Midnight after the 25-hour Sunday is still Sunday 24:00.
        XCTAssertEqual(zh(utc(2026, 11, 2, 5), now: nyNow, calendar: ny), "明天 24:00")      // Mon 00:00 EST
    }
}
