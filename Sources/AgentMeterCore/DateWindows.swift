import Foundation

/// Computes the "today" and "rolling N-hour" time windows used to bucket usage.
///
/// All agent timestamps are stored in UTC; day boundaries are evaluated in the
/// supplied calendar's time zone so "today" matches the user's wall clock.
public struct DateWindows: Sendable {
    public let now: Date
    public let todayStart: Date
    public let rollingWindowStart: Date
    private let calendar: Calendar

    public init(now: Date, calendar: Calendar = .current, rollingHours: Double = 5) {
        self.now = now
        self.calendar = calendar
        self.todayStart = calendar.startOfDay(for: now)
        self.rollingWindowStart = now.addingTimeInterval(-rollingHours * 3600)
    }

    /// The earliest instant either window cares about — used to skip clearly-old files.
    public var earliestRelevant: Date { min(todayStart, rollingWindowStart) }

    /// True when `date` falls on the same calendar day as `now` (local time).
    public func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    /// True when `date` is within the rolling window ending at `now`.
    public func isInRollingWindow(_ date: Date) -> Bool {
        date >= rollingWindowStart && date <= now
    }
}
