import XCTest
@testable import AgentMeterCore

final class QuotaMergeTests: XCTestCase {
    private let now = utc(2026, 6, 14, 2)
    private let future = utc(2026, 6, 14, 5)
    private let past = utc(2026, 6, 14, 1)

    func testNormalizeExpiredResetsToZero() {
        let r = QuotaMerge.normalize(QuotaWindow(usedPercent: 80, resetsAt: past), now: now)
        XCTAssertEqual(r, QuotaWindow(usedPercent: 0, resetsAt: nil))
    }

    func testNormalizeKeepsFutureReset() {
        let w = QuotaWindow(usedPercent: 80, resetsAt: future)
        XCTAssertEqual(QuotaMerge.normalize(w, now: now), w)
    }

    func testNormalizeKeepsNilReset() {
        let w = QuotaWindow(usedPercent: 33, resetsAt: nil)
        XCTAssertEqual(QuotaMerge.normalize(w, now: now), w)
    }

    func testMergePrefersFresh() {
        let prev = QuotaWindow(usedPercent: 10, resetsAt: future)
        let fresh = QuotaWindow(usedPercent: 20, resetsAt: future)
        XCTAssertEqual(QuotaMerge.merge(previous: prev, fresh: fresh, now: now), fresh)
    }

    func testMergeKeepsPreviousWhenFreshNil() {
        let prev = QuotaWindow(usedPercent: 10, resetsAt: future)
        XCTAssertEqual(QuotaMerge.merge(previous: prev, fresh: nil, now: now), prev)
    }

    func testMergePreviousExpiredBecomesZero() {
        let prev = QuotaWindow(usedPercent: 90, resetsAt: past)
        XCTAssertEqual(QuotaMerge.merge(previous: prev, fresh: nil, now: now),
                       QuotaWindow(usedPercent: 0, resetsAt: nil))
    }

    func testMergeBothNilIsNil() {
        XCTAssertNil(QuotaMerge.merge(previous: nil, fresh: nil, now: now))
    }

    func testMergeNormalizesExpiredFreshValue() {
        let fresh = QuotaWindow(usedPercent: 47, resetsAt: past)
        let prev = QuotaWindow(usedPercent: 10, resetsAt: future)
        XCTAssertEqual(QuotaMerge.merge(previous: prev, fresh: fresh, now: now),
                       QuotaWindow(usedPercent: 0, resetsAt: nil))
    }

    func testNormalizeResetExactlyNowCountsAsReset() {
        let r = QuotaMerge.normalize(QuotaWindow(usedPercent: 60, resetsAt: now), now: now)
        XCTAssertEqual(r, QuotaWindow(usedPercent: 0, resetsAt: nil))
    }
}
