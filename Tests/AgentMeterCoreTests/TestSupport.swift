import Foundation
import XCTest

/// A fixed calendar in a known time zone so day-boundary tests are deterministic
/// regardless of where they run.
let taipei = TimeZone(identifier: "Asia/Taipei")!

var taipeiCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = taipei
    return c
}()

/// Build a UTC instant from explicit components.
func utc(_ year: Int, _ month: Int, _ day: Int,
         _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day
    c.hour = hour; c.minute = minute; c.second = second
    c.timeZone = TimeZone(identifier: "UTC")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = c.timeZone!
    return cal.date(from: c)!
}

/// ISO-8601 string with millis + Z, the format both Claude Code and Codex write.
func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")!
    return f.string(from: date)
}

/// Create a temporary directory unique to one test; caller cleans up.
func makeTempDir(_ name: String = "agentmeter-test") throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent(name, isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

func writeLines(_ lines: [String], to file: URL) throws {
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
}
