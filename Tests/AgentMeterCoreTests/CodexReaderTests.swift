import XCTest
@testable import AgentMeterCore

final class CodexReaderTests: XCTestCase {
    // now = 2026-06-14 10:00 Taipei == 02:00 UTC
    private let now = utc(2026, 6, 14, 2)

    private func reader(_ dir: URL) -> CodexReader {
        CodexReader(sessionsDirectory: dir, calendar: taipeiCalendar, rollingHours: 5)
    }

    private func tokenCount(ts: Date, input: Int, cached: Int, output: Int, reasoning: Int) -> String {
        let total = input + output
        return """
        {"timestamp":"\(iso(ts))","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)},"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)}}}}
        """
    }

    private func agentMessage(ts: Date) -> String {
        """
        {"timestamp":"\(iso(ts))","type":"event_msg","payload":{"type":"agent_message","message":"hi"}}
        """
    }

    private func sessionMeta(ts: Date) -> String {
        """
        {"timestamp":"\(iso(ts))","type":"session_meta","payload":{"id":"abc"}}
        """
    }

    func testMissingDirectoryReportsUnavailable() throws {
        let usage = try reader(URL(fileURLWithPath: "/no/such/codex/sessions")).read(now: now)
        XCTAssertFalse(usage.available)
        XCTAssertEqual(usage.messageCount, 0)
    }

    func testSumsDeltasBucketsWindowsAndCountsAgentMessages() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = [
            sessionMeta(ts: utc(2026, 6, 14, 1)),
            // 09:00 Taipei: today + within 5h
            agentMessage(ts: utc(2026, 6, 14, 1)),
            tokenCount(ts: utc(2026, 6, 14, 1), input: 1000, cached: 200, output: 100, reasoning: 30),
            // 04:00 Taipei: today but 6h ago (outside 5h)
            agentMessage(ts: utc(2026, 6, 13, 20)),
            tokenCount(ts: utc(2026, 6, 13, 20), input: 500, cached: 0, output: 50, reasoning: 0),
            // previous local day: excluded entirely
            agentMessage(ts: utc(2026, 6, 13, 14)),
            tokenCount(ts: utc(2026, 6, 13, 14), input: 9999, cached: 0, output: 9999, reasoning: 0),
            "not json at all",
        ]
        try writeLines(lines, to: dir.appendingPathComponent("2026/06/14/rollout-test.jsonl"))

        let usage = try reader(dir).read(now: now)

        XCTAssertTrue(usage.available)
        // today = first two token_count events. Codex total_tokens == input + output,
        // cached is a subset of input, reasoning a subset of output.
        // event1: input 1000(-200 cached)=800, cacheRead 200, output 100(-30)=70, reasoning 30  (total 1100)
        // event2: input 500, output 50                                                          (total 550)
        XCTAssertEqual(usage.today, TokenBreakdown(input: 1300, output: 120,
                                                   cacheCreation: 0, cacheRead: 200, reasoning: 30))
        XCTAssertEqual(usage.today.total, 1650)
        // rolling 5h = event1 only
        XCTAssertEqual(usage.rolling5h, TokenBreakdown(input: 800, output: 70,
                                                       cacheCreation: 0, cacheRead: 200, reasoning: 30))
        // two agent_message events fall on today
        XCTAssertEqual(usage.messageCount, 2)
    }
}
