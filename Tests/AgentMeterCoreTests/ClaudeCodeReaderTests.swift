import XCTest
@testable import AgentMeterCore

final class ClaudeCodeReaderTests: XCTestCase {
    // now = 2026-06-14 10:00 Taipei == 02:00 UTC
    private let now = utc(2026, 6, 14, 2)

    private func reader(_ dir: URL) -> ClaudeCodeReader {
        ClaudeCodeReader(projectsDirectory: dir, calendar: taipeiCalendar, rollingHours: 5)
    }

    private func assistantLine(ts: Date, id: String, req: String,
                               input: Int, output: Int, cc: Int, cr: Int,
                               model: String = "claude-test") -> String {
        """
        {"type":"assistant","timestamp":"\(iso(ts))","requestId":"\(req)","message":{"id":"\(id)","role":"assistant","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cc),"cache_read_input_tokens":\(cr)}}}
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

    func testTodayByModelBucketsByNormalizedKeyAndSumsToToday() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let opus = assistantLine(ts: utc(2026, 6, 14, 1), id: "m1", req: "r1",
                                 input: 100, output: 50, cc: 10, cr: 20, model: "claude-opus-4-8")
        // dated snapshot must normalize to the base key "claude-haiku-4-5"
        let haiku = assistantLine(ts: utc(2026, 6, 14, 1, 10), id: "m2", req: "r2",
                                  input: 200, output: 100, cc: 0, cr: 0, model: "claude-haiku-4-5-20251001")
        try writeLines([opus, haiku], to: dir.appendingPathComponent("p/s.jsonl"))

        let usage = try reader(dir).read(now: now)

        XCTAssertEqual(usage.todayByModel["claude-opus-4-8"],
                       TokenBreakdown(input: 100, output: 50, cacheCreation: 10, cacheRead: 20))
        XCTAssertEqual(usage.todayByModel["claude-haiku-4-5"],
                       TokenBreakdown(input: 200, output: 100))
        // parity: per-model buckets sum to the flat `today` total
        let summed = usage.todayByModel.values.reduce(TokenBreakdown(), +)
        XCTAssertEqual(summed, usage.today)
    }

    func testContextWindowFromLatestTurnUses1MForOneMillionModel() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let older = assistantLine(ts: utc(2026, 6, 14, 0), id: "old", req: "r0",
                                  input: 10, output: 10, cc: 0, cr: 0, model: "claude-x")
        // latest turn (largest timestamp) — its context fill is what we report
        let latest = assistantLine(ts: utc(2026, 6, 14, 1, 30), id: "new", req: "r1",
                                   input: 50_000, output: 1_000, cc: 4_000, cr: 6_000,
                                   model: "claude-opus-4-8[1m]")
        try writeLines([older, latest], to: dir.appendingPathComponent("p/s.jsonl"))

        let usage = try reader(dir).read(now: now)
        // used = input + cacheRead + cacheCreation = 50_000 + 6_000 + 4_000
        XCTAssertEqual(usage.contextWindow, ContextWindow(used: 60_000, total: 1_000_000))
    }

    func testContextWindowInfers1MWhenUsedExceeds200kWithoutTag() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Real transcripts record the model WITHOUT the [1m] suffix, so a >200k
        // context must be a 1M session.
        let line = assistantLine(ts: utc(2026, 6, 14, 1), id: "m", req: "r",
                                 input: 250_000, output: 100, cc: 0, cr: 0, model: "claude-opus-4-8")
        try writeLines([line], to: dir.appendingPathComponent("p/s.jsonl"))

        let usage = try reader(dir).read(now: now)
        XCTAssertEqual(usage.contextWindow, ContextWindow(used: 250_000, total: 1_000_000))
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
