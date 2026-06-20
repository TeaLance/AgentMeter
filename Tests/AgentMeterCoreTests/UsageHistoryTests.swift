import XCTest
@testable import AgentMeterCore

final class UsageHistoryTests: XCTestCase {
    private let range = DateInterval(start: utc(2026, 6, 10), end: utc(2026, 6, 20))

    // MARK: Claude

    private func claudeLine(ts: Date, id: String, input: Int, output: Int, model: String) -> String {
        """
        {"type":"assistant","timestamp":"\(iso(ts))","requestId":"\(id)","message":{"id":"\(id)","role":"assistant","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    func testClaudeHistoryBucketsByDayAndModelWithDedup() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let d14a = claudeLine(ts: utc(2026, 6, 14, 1), id: "a", input: 100, output: 10, model: "claude-opus-4-8")
        let d14aDup = d14a   // resume duplicate, must not double-count
        let d14b = claudeLine(ts: utc(2026, 6, 14, 3), id: "b", input: 200, output: 20,
                              model: "claude-haiku-4-5-20251001")  // normalizes to claude-haiku-4-5
        let d13 = claudeLine(ts: utc(2026, 6, 13, 1), id: "c", input: 50, output: 5, model: "claude-opus-4-8")
        let outOfRange = claudeLine(ts: utc(2026, 6, 1, 1), id: "z", input: 9, output: 9, model: "claude-opus-4-8")

        try writeLines([d14a, d14aDup, d14b, d13, outOfRange],
                       to: dir.appendingPathComponent("p/s.jsonl"))

        let h = try ClaudeCodeReader(projectsDirectory: dir, calendar: taipeiCalendar).history(range: range)

        // out-of-range excluded; 3 distinct rows across 2 Taipei days
        XCTAssertEqual(h.days.count, 2)
        XCTAssertEqual(h.messageCount, 3)
        XCTAssertEqual(h.byModel["claude-opus-4-8"], TokenBreakdown(input: 150, output: 15))
        XCTAssertEqual(h.byModel["claude-haiku-4-5"], TokenBreakdown(input: 200, output: 20))
        // ascending by day
        XCTAssertTrue(h.days[0].day < h.days[1].day)
        // the later day has both models
        let day14 = h.days[1]
        XCTAssertEqual(day14.byModel["claude-opus-4-8"], TokenBreakdown(input: 100, output: 10))
        XCTAssertEqual(day14.byModel["claude-haiku-4-5"], TokenBreakdown(input: 200, output: 20))
    }

    // MARK: Codex

    private func turnContext(ts: Date, model: String) -> String {
        """
        {"timestamp":"\(iso(ts))","type":"turn_context","payload":{"type":"turn_context","model":"\(model)"}}
        """
    }

    private func tokenCount(ts: Date, input: Int, output: Int) -> String {
        """
        {"timestamp":"\(iso(ts))","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":272000,"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)}}}}
        """
    }

    func testCodexHistoryAttributesTokensToCurrentModel() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // One file, two models in sequence — the state machine must partition them.
        let lines = [
            turnContext(ts: utc(2026, 6, 14, 0, 50), model: "gpt-5.5"),
            tokenCount(ts: utc(2026, 6, 14, 1), input: 1000, output: 100),
            turnContext(ts: utc(2026, 6, 14, 1, 30), model: "gpt-5.4"),
            tokenCount(ts: utc(2026, 6, 14, 2), input: 500, output: 50),
        ]
        try writeLines(lines, to: dir.appendingPathComponent("2026/06/14/rollout-a.jsonl"))

        let h = try CodexReader(sessionsDirectory: dir, calendar: taipeiCalendar).history(range: range)

        XCTAssertEqual(h.byModel["gpt-5.5"], TokenBreakdown(input: 1000, output: 100))
        XCTAssertEqual(h.byModel["gpt-5.4"], TokenBreakdown(input: 500, output: 50))
    }

    func testCodexHistoryTokenCountBeforeAnyTurnContextIsUnknown() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeLines([tokenCount(ts: utc(2026, 6, 14, 1), input: 300, output: 30)],
                       to: dir.appendingPathComponent("2026/06/14/rollout-b.jsonl"))

        let h = try CodexReader(sessionsDirectory: dir, calendar: taipeiCalendar).history(range: range)
        XCTAssertEqual(h.byModel[ModelKey.unknown.id], TokenBreakdown(input: 300, output: 30))
    }

    func testCodexModelStateResetsPerFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // File 1 establishes gpt-5.5; file 2 must NOT inherit it.
        try writeLines([turnContext(ts: utc(2026, 6, 13, 1), model: "gpt-5.5"),
                        tokenCount(ts: utc(2026, 6, 13, 1, 5), input: 10, output: 1)],
                       to: dir.appendingPathComponent("2026/06/13/rollout-1.jsonl"))
        try writeLines([tokenCount(ts: utc(2026, 6, 14, 1), input: 20, output: 2)],
                       to: dir.appendingPathComponent("2026/06/14/rollout-2.jsonl"))

        let h = try CodexReader(sessionsDirectory: dir, calendar: taipeiCalendar).history(range: range)
        XCTAssertEqual(h.byModel["gpt-5.5"], TokenBreakdown(input: 10, output: 1))
        XCTAssertEqual(h.byModel[ModelKey.unknown.id], TokenBreakdown(input: 20, output: 2))
    }
}
