import Foundation

/// When a quota window resets, in wall-clock words for the dropdown panel:
/// "今天 23:00", "明天 09:00", "星期四 23:00", "下星期四 23:00" (same weekday a
/// week out), or "11/27 23:00" beyond that. English: "today 23:00",
/// "tomorrow 09:00", "Thu 23:00", "next Thu 23:00", "11/27 23:00".
public enum ResetMoment {
    public enum Language: Sendable { case zh, en }

    /// Nil when there is no reset time or it is not in the future.
    /// "Today"/"tomorrow" are calendar days in `calendar`'s time zone, not 24-hour spans.
    public static func text(for date: Date?, now: Date = Date(),
                            calendar: Calendar = .autoupdatingCurrent,
                            language: Language) -> String? {
        guard let date, date > now else { return nil }
        // Reset times derived from "seconds remaining" drift by a few seconds
        // (22:59:47); round to the nearest minute so the clock reads 23:00.
        let rounded = Date(timeIntervalSinceReferenceDate:
            (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        // Only the time zone comes from the caller's calendar: a system set to a
        // lunar/other calendar would otherwise print its own month/day ("10/19").
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        let c = g.dateComponents([.month, .day, .hour, .minute, .weekday], from: rounded)
        guard let month = c.month, let day = c.day, let hour = c.hour, let minute = c.minute,
              let weekday = c.weekday, (1...7).contains(weekday),
              let days = g.dateComponents([.day], from: g.startOfDay(for: now),
                                          to: g.startOfDay(for: rounded)).day
        else { return nil }

        let dayText: String
        switch (days, language) {
        case (...0, .zh): dayText = "今天"
        case (...0, .en): dayText = "today"
        case (1, .zh): dayText = "明天"
        case (1, .en): dayText = "tomorrow"
        case (2...6, .zh): dayText = zhWeekdays[weekday - 1]
        case (2...6, .en): dayText = enWeekdays[weekday - 1]
        case (7, .zh): dayText = "下" + zhWeekdays[weekday - 1]
        case (7, .en): dayText = "next " + enWeekdays[weekday - 1]
        default: dayText = "\(month)/\(day)"
        }
        return "\(dayText) " + String(format: "%02d:%02d", hour, minute)
    }

    // Foundation's weekday: 1 = Sunday … 7 = Saturday.
    private static let zhWeekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    private static let enWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}
