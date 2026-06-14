import XCTest
@testable import AgentMeterCore

final class ClaudeStatusReaderTests: XCTestCase {
    private func write(_ json: String) throws -> URL {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("agentmeter-status.json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func testMissingFileIsUnavailable() {
        let q = ClaudeStatusReader(statusFile: URL(fileURLWithPath: "/no/such/status.json")).read()
        XCTAssertFalse(q.available)
        XCTAssertNil(q.fiveHour)
    }

    func testBadJsonIsUnavailable() throws {
        let file = try write("{ not json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        XCTAssertFalse(ClaudeStatusReader(statusFile: file).read().available)
    }

    func testParsesFiveHourAndWeeklyWithISOReset() throws {
        let file = try write(#"""
        {
          "asOf": "2026-06-14T15:00:00Z",
          "model": "Opus 4.8",
          "rate_limits": {
            "five_hour": { "used_percentage": 39.4, "resets_at": "2026-06-14T17:00:00Z" },
            "seven_day": { "used_percentage": 14.0, "resets_at": "2026-06-18T15:00:00Z" }
          }
        }
        """#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let q = ClaudeStatusReader(statusFile: file).read()
        XCTAssertTrue(q.available)
        XCTAssertEqual(q.fiveHour?.usedPercent ?? 0, 39.4, accuracy: 1e-6)
        XCTAssertEqual(q.fiveHour?.resetsAt, utc(2026, 6, 14, 17))
        XCTAssertEqual(q.weekly?.usedPercent ?? 0, 14.0, accuracy: 1e-6)
        XCTAssertEqual(q.asOf, utc(2026, 6, 14, 15))
    }

    func testToleratesEpochSecondsReset() throws {
        let epoch = utc(2026, 6, 14, 17).timeIntervalSince1970
        let file = try write(#"""
        { "rate_limits": { "five_hour": { "used_percentage": 50, "resets_at": \#(Int(epoch)) } } }
        """#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let q = ClaudeStatusReader(statusFile: file).read()
        XCTAssertEqual(q.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0, epoch, accuracy: 1.0)
    }

    func testParsesContextWindowTokens() throws {
        let file = try write(#"""
        {
          "context_window": { "used_percentage": 6.4, "total_input_tokens": 63900, "max_tokens": 1000000 }
        }
        """#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let q = ClaudeStatusReader(statusFile: file).read()
        XCTAssertEqual(q.contextWindow, ContextWindow(used: 63_900, total: 1_000_000))
        XCTAssertEqual(q.contextPercent ?? 0, 6.4, accuracy: 1e-6)
    }

    func testNoRateLimitsStillAvailableButNilWindows() throws {
        let file = try write(#"{ "asOf": "2026-06-14T15:00:00Z" }"#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let q = ClaudeStatusReader(statusFile: file).read()
        XCTAssertTrue(q.available)
        XCTAssertNil(q.fiveHour)
        XCTAssertNil(q.weekly)
    }
}
