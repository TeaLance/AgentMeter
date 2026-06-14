import XCTest
@testable import AgentMeterCore

final class ClaudeCodeReaderTests: XCTestCase {
    // now = 2026-06-14 10:00 Taipei == 02:00 UTC
    private let now = utc(2026, 6, 14, 2)

    private func reader(_ dir: URL) -> ClaudeCodeReader {
        ClaudeCodeReader(projectsDirectory: dir, calendar: taipeiCalendar, rollingHours: 5)
    }

    private func assistantLine(ts: Date, id: String, req: String,
                               input: Int, output: Int, cc: Int, cr: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(iso(ts))","requestId":"\(req)","message":{"id":"\(id)","role":"assistant","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cc),"cache_read_input_tokens":\(cr)}}}
        """
    }

    private func userLine(ts: Date) -> String {
        """
        {"type":"user","timestamp":"\(iso(ts))","message":{"role":"user","content":"hi"}}
        """
    }

    func testMissingDirectoryReportsUnavailable() throws {
        let usage = try reader(URL(fileURLWithPath: "/no/such/claude/projects")).read(now: now)
        XCTAssertFalse(usage.available)
        XCTAssertEqual(usage.today, TokenBreakdown())
        XCTAssertEqual(usage.messageCount, 0)
    }

    func testAggregatesTodayDedupsAndBucketsRollingWindow() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = assistantLine(ts: utc(2026, 6, 14, 1),     // 09:00 Taipei: today + within 5h
                              id: "m1", req: "r1", input: 100, output: 50, cc: 10, cr: 20)
        let aDup = a                                         // exact resume duplicate
        let b = assistantLine(ts: utc(2026, 6, 13, 20),    // 04:00 Taipei: today but 6h ago (outside 5h)
                              id: "m2", req: "r2", input: 200, output: 100, cc: 0, cr: 0)
        let c = assistantLine(ts: utc(2026, 6, 13, 14),    // 22:00 Taipei prev day: not today
                              id: "m3", req: "r3", input: 999, output: 999, cc: 0, cr: 0)
        let user = userLine(ts: utc(2026, 6, 14, 1))        // not a usage row
        let garbage = "this is not json"

        try writeLines([user, a, aDup, b, c, garbage],
                       to: dir.appendingPathComponent("proj-x/session1.jsonl"))

        let usage = try reader(dir).read(now: now)

        XCTAssertTrue(usage.available)
        // today = a + b (dup of a counted once, c excluded)
        XCTAssertEqual(usage.today, TokenBreakdown(input: 300, output: 150, cacheCreation: 10, cacheRead: 20))
        XCTAssertEqual(usage.today.total, 480)
        // two distinct assistant responses today
        XCTAssertEqual(usage.messageCount, 2)
        // rolling 5h = a only
        XCTAssertEqual(usage.rolling5h, TokenBreakdown(input: 100, output: 50, cacheCreation: 10, cacheRead: 20))
    }

    func testDedupAcrossSeparateSessionFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let line = assistantLine(ts: utc(2026, 6, 14, 1), id: "dup", req: "rq",
                                 input: 10, output: 10, cc: 0, cr: 0)
        try writeLines([line], to: dir.appendingPathComponent("proj-a/s1.jsonl"))
        try writeLines([line], to: dir.appendingPathComponent("proj-b/s2.jsonl")) // resumed elsewhere

        let usage = try reader(dir).read(now: now)
        XCTAssertEqual(usage.messageCount, 1)
        XCTAssertEqual(usage.today.total, 20)
    }
}
