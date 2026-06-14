import XCTest
@testable import AgentMeterCore

final class DateWindowsTests: XCTestCase {
    // now = 2026-06-14 10:00 Taipei == 2026-06-14 02:00 UTC
    private func windows() -> DateWindows {
        DateWindows(now: utc(2026, 6, 14, 2), calendar: taipeiCalendar, rollingHours: 5)
    }

    func testSameLocalDayCountsAsToday() {
        // 2026-06-14 09:00 Taipei == 01:00 UTC -> same Taipei day
        XCTAssertTrue(windows().isToday(utc(2026, 6, 14, 1)))
    }

    func testEarlierUTCButStillTodayLocally() {
        // 2026-06-13 17:00 UTC == 2026-06-14 01:00 Taipei -> today (Taipei)
        XCTAssertTrue(windows().isToday(utc(2026, 6, 13, 17)))
    }

    func testPreviousLocalDayIsNotToday() {
        // 2026-06-13 15:00 UTC == 2026-06-13 23:00 Taipei -> yesterday
        XCTAssertFalse(windows().isToday(utc(2026, 6, 13, 15)))
    }

    func testWithinRollingWindow() {
        // 30 min ago
        XCTAssertTrue(windows().isInRollingWindow(utc(2026, 6, 14, 1, 30)))
    }

    func testOutsideRollingWindow() {
        // 6h ago, before the 5h window start
        XCTAssertFalse(windows().isInRollingWindow(utc(2026, 6, 13, 20)))
    }
}
