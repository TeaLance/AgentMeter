import XCTest
@testable import AgentMeterCore

final class CodexLocalQuotaReaderTests: XCTestCase {
    private func line(_ ts: Date, _ limits: String) -> String {
        #"{"timestamp":"\#(iso(ts))","type":"event_msg","payload":{"type":"token_count","rate_limits":\#(limits)}}"#
    }

    private func limits(p: Double, pr: Int, s: Double, sr: Int, pm: Int = 300, sm: Int = 10080) -> String {
        #"{"limit_id":"codex","primary":{"used_percent":\#(p),"window_minutes":\#(pm),"resets_at":\#(pr)},"secondary":{"used_percent":\#(s),"window_minutes":\#(sm),"resets_at":\#(sr)}}"#
    }

    private func setFile(_ dir: URL, _ name: String, _ lines: [String], age: TimeInterval) throws {
        let url = dir.appendingPathComponent(name)
        try writeLines(lines, to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private func tmp() throws -> URL {
        let d = try makeTempDir()
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func testParsesResetsAt() throws {
        let dir = try tmp()
        let ts = utc(2026, 6, 14, 1)
        try setFile(dir, "2026/06/14/rollout-a.jsonl",
                    [line(ts, limits(p: 47, pr: 1_793_382_366, s: 25, sr: 1_793_810_079))], age: 0)
        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.fiveHour, QuotaWindow(usedPercent: 47, resetsAt: Date(timeIntervalSince1970: 1_793_382_366)))
        XCTAssertEqual(r?.weekly, QuotaWindow(usedPercent: 25, resetsAt: Date(timeIntervalSince1970: 1_793_810_079)))
        XCTAssertEqual(r?.timestamp, ts)
    }

    func testFallsBackToOlderFileWhenNewestHasNoRateLimits() throws {
        let dir = try tmp()
        try setFile(dir, "old.jsonl", [line(utc(2026, 6, 14, 1), limits(p: 11, pr: 2_000_000_000, s: 5, sr: 2_000_100_000))], age: 100)
        try setFile(dir, "new.jsonl", [#"{"timestamp":"2026-06-14T02:00:00Z","type":"event_msg","payload":{"type":"token_count"}}"#], age: 0)
        XCTAssertEqual(CodexLocalQuotaReader(sessionsDirectory: dir).read()?.fiveHour?.usedPercent, 11)
    }

    func testLastEntryInFileWins() throws {
        let dir = try tmp()
        try setFile(dir, "a.jsonl", [
            line(utc(2026, 6, 14, 1), limits(p: 10, pr: 2_000_000_000, s: 1, sr: 2_000_100_000)),
            line(utc(2026, 6, 14, 2), limits(p: 20, pr: 2_000_000_000, s: 2, sr: 2_000_100_000)),
        ], age: 0)
        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.fiveHour?.usedPercent, 20)
        XCTAssertEqual(r?.timestamp, utc(2026, 6, 14, 2))
    }

    func testNullRateLimitsSkippedAndPrimaryOnly() throws {
        let dir = try tmp()
        try setFile(dir, "a.jsonl", [
            line(utc(2026, 6, 14, 1), #"{"primary":{"used_percent":33.0,"window_minutes":300,"resets_at":2000000000},"secondary":null}"#),
            line(utc(2026, 6, 14, 2), "null"),
        ], age: 0)
        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.fiveHour?.usedPercent, 33)
        XCTAssertNil(r?.weekly)
        XCTAssertEqual(r?.timestamp, utc(2026, 6, 14, 1))
    }

    func testBadLinesSkipped() throws {
        let dir = try tmp()
        try setFile(dir, "a.jsonl", [
            line(utc(2026, 6, 14, 1), limits(p: 40, pr: 2_000_000_000, s: 4, sr: 2_000_100_000)),
            "{not json", #"{"timestamp":"bad","payload":{"rate_limits":{"primary":{"used_percent":99}}}}"#,
            #"{"timestamp":"2026-06-14T03:00:00Z","payload":{"rate_limits":{"primary":{}}}}"#,
        ], age: 0)
        XCTAssertEqual(CodexLocalQuotaReader(sessionsDirectory: dir).read()?.fiveHour?.usedPercent, 40)
    }

    func testWindowMinutesMapsEvenWhenSwapped() throws {
        let dir = try tmp()
        try setFile(dir, "a.jsonl", [
            line(utc(2026, 6, 14, 1), limits(p: 70, pr: 2_000_100_000, s: 15, sr: 2_000_000_000, pm: 10080, sm: 300)),
        ], age: 0)
        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.weekly?.usedPercent, 70)
        XCTAssertEqual(r?.fiveHour?.usedPercent, 15)
    }

    func testPositionalMappingWithoutWindowMinutes() throws {
        let dir = try tmp()
        try setFile(dir, "a.jsonl", [
            line(utc(2026, 6, 14, 1), #"{"primary":{"used_percent":8},"secondary":{"used_percent":9}}"#),
        ], age: 0)
        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.fiveHour?.usedPercent, 8)
        XCTAssertEqual(r?.weekly?.usedPercent, 9)
    }

    func testResetsInSecondsRelativeToLineTimestamp() throws {
        let dir = try tmp()
        let ts = utc(2026, 6, 14, 1)
        try setFile(dir, "a.jsonl", [
            line(ts, #"{"primary":{"used_percent":8,"window_minutes":300,"resets_in_seconds":600}}"#),
        ], age: 0)
        XCTAssertEqual(CodexLocalQuotaReader(sessionsDirectory: dir).read()?.fiveHour?.resetsAt,
                       ts.addingTimeInterval(600))
    }

    func testEmptyOrMissingDirectoryReturnsNil() throws {
        let dir = try tmp()
        XCTAssertNil(CodexLocalQuotaReader(sessionsDirectory: dir).read())
        XCTAssertNil(CodexLocalQuotaReader(sessionsDirectory: URL(fileURLWithPath: "/no/such/dir")).read())
    }

    func testNewerFileWinsWhenBothHaveLimits() throws {
        let dir = try tmp()
        // Names deliberately sort opposite to mtime; mtimes are set explicitly.
        try setFile(dir, "z-old.jsonl", [line(utc(2026, 6, 14, 1), limits(p: 11, pr: 2_000_000_000, s: 1, sr: 2_000_100_000))], age: 1000)
        try setFile(dir, "a-new.jsonl", [line(utc(2026, 6, 14, 2), limits(p: 22, pr: 2_000_000_000, s: 2, sr: 2_000_100_000))], age: 10)
        XCTAssertEqual(CodexLocalQuotaReader(sessionsDirectory: dir).read()?.fiveHour?.usedPercent, 22)
    }

    func testResetsAtInMillisecondsIsConverted() throws {
        let dir = try tmp()
        try setFile(dir, "a.jsonl", [
            line(utc(2026, 6, 14, 1), #"{"primary":{"used_percent":8,"window_minutes":300,"resets_at":1793382366000}}"#),
        ], age: 0)
        XCTAssertEqual(CodexLocalQuotaReader(sessionsDirectory: dir).read()?.fiveHour?.resetsAt,
                       Date(timeIntervalSince1970: 1_793_382_366))
    }

    /// The 1 MB tail begins exactly at the start of a valid rate_limits JSON that is glued
    /// behind garbage on the same physical line. If the partial first line were not dropped,
    /// it would be parsed as 99%; dropping it falls through to the older file (12%).
    func testTruncatedFirstLineIsDroppedEvenWhenRemainderLooksValid() throws {
        let dir = try tmp()
        try setFile(dir, "old.jsonl", [line(utc(2026, 6, 14, 1), limits(p: 12, pr: 2_000_000_000, s: 1, sr: 2_000_100_000))], age: 1000)

        let trap = line(utc(2026, 6, 14, 2), limits(p: 99, pr: 2_000_000_000, s: 9, sr: 2_000_100_000))
        let junk = "GARBAGE-PREFIX"
        let tail = 1_048_576
        // tail = trap + "\n" + filler + "\n"  (exactly 1 MB), file = junk + tail
        let fillerPrefix = #"{"type":"event_msg","payload":{"type":"x","pad":""#
        let fillerSuffix = #""}}"#
        let fillerLen = tail - (trap.utf8.count + 1) - 1
        let pad = String(repeating: "a", count: fillerLen - fillerPrefix.utf8.count - fillerSuffix.utf8.count)
        let content = junk + trap + "\n" + fillerPrefix + pad + fillerSuffix + "\n"
        let url = dir.appendingPathComponent("big.jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        XCTAssertEqual(content.utf8.count, tail + junk.utf8.count)

        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.fiveHour?.usedPercent, 12)
    }

    func testOnlyTailOfLargeFileIsRead() throws {
        let dir = try tmp()
        let good = line(utc(2026, 6, 14, 1), limits(p: 55, pr: 2_000_000_000, s: 6, sr: 2_000_100_000))
        // Valid-looking rate_limits line buried > 1 MB from the end must NOT be seen.
        let buried = line(utc(2026, 6, 14, 0), limits(p: 99, pr: 2_000_000_000, s: 99, sr: 2_000_100_000))
        let filler = #"{"timestamp":"2026-06-14T00:30:00Z","type":"event_msg","payload":{"type":"x","pad":""# + String(repeating: "a", count: 4000) + #""}}"#
        var lines = [buried]
        lines += Array(repeating: filler, count: 300)   // ~1.2 MB
        lines.append(good)
        let url = dir.appendingPathComponent("big.jsonl")
        try writeLines(lines, to: url)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber).intValue
        XCTAssertGreaterThan(size, 1_048_576)
        let r = CodexLocalQuotaReader(sessionsDirectory: dir).read()
        XCTAssertEqual(r?.fiveHour?.usedPercent, 55)

        // Only the buried line carries limits -> tail has none -> nil, no crash.
        try writeLines([buried] + Array(repeating: filler, count: 300), to: url)
        XCTAssertNil(CodexLocalQuotaReader(sessionsDirectory: dir).read())
    }
}
