import XCTest
@testable import AgentMeterCore

// MARK: - Legacy reference (verbatim port of the pre-cache read(now:) logic)

private struct LClaudeLine: Decodable { let timestamp: String?; let requestId: String?; let message: LClaudeMsg? }
private struct LClaudeMsg: Decodable { let id: String?; let model: String?; let usage: LClaudeUsage? }
private struct LClaudeUsage: Decodable {
    let inputTokens: Int?; let outputTokens: Int?
    let cacheCreationInputTokens: Int?; let cacheReadInputTokens: Int?
}
private struct LCodexLine: Decodable { let timestamp: String?; let type: String?; let payload: LCodexPayload? }
private struct LCodexPayload: Decodable { let type: String?; let info: LCodexInfo?; let model: String? }
private struct LCodexInfo: Decodable {
    let lastTokenUsage: LCodexUsage?
    let totalTokenUsage: LCodexUsage?
    let modelContextWindow: Int?
}
private struct LCodexUsage: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?
    var breakdown: TokenBreakdown {
        let cached = cachedInputTokens ?? 0
        let reasoning = reasoningOutputTokens ?? 0
        return TokenBreakdown(input: max(0, (inputTokens ?? 0) - cached),
                              output: max(0, (outputTokens ?? 0) - reasoning),
                              cacheCreation: 0, cacheRead: cached, reasoning: reasoning)
    }
}

func legacyClaudeRead(dir: URL, calendar: Calendar, now: Date, rollingHours: Double = 5) -> ToolUsage {
    guard directoryExists(dir) else { return ToolUsage(tool: .claudeCode, available: false, lastUpdated: now) }
    let windows = DateWindows(now: now, calendar: calendar, rollingHours: rollingHours)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var today = TokenBreakdown(), rolling = TokenBreakdown()
    var messageCount = 0
    var todayByModel: [String: TokenBreakdown] = [:]
    var seen = Set<String>()
    var latestTimestamp: Date?
    var latestContextUsed = 0
    var latestModel: String?
    for file in jsonlFiles(in: dir) {
        if modificationDate(of: file) < windows.earliestRelevant { continue }
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8),
                  let line = try? decoder.decode(LClaudeLine.self, from: data),
                  let usage = line.message?.usage,
                  let tsString = line.timestamp,
                  let timestamp = parseISOTimestamp(tsString) else { continue }
            if let id = line.message?.id {
                let key = "\(id)|\(line.requestId ?? "")"
                if !seen.insert(key).inserted { continue }
            }
            let breakdown = TokenBreakdown(input: usage.inputTokens ?? 0, output: usage.outputTokens ?? 0,
                                           cacheCreation: usage.cacheCreationInputTokens ?? 0,
                                           cacheRead: usage.cacheReadInputTokens ?? 0)
            if windows.isToday(timestamp) {
                today += breakdown
                messageCount += 1
                todayByModel[ModelKey(raw: line.message?.model ?? "").id, default: TokenBreakdown()] += breakdown
            }
            if windows.isInRollingWindow(timestamp) { rolling += breakdown }
            if latestTimestamp == nil || timestamp > latestTimestamp! {
                latestTimestamp = timestamp
                latestContextUsed = breakdown.input + breakdown.cacheRead + breakdown.cacheCreation
                latestModel = line.message?.model
            }
        }
    }
    let contextWindow = latestTimestamp.map { _ -> ContextWindow in
        let tagged = AgentMeterCore.contextWindow(forModelID: latestModel)
        return ContextWindow(used: latestContextUsed, total: latestContextUsed > 200_000 ? 1_000_000 : tagged)
    }
    return ToolUsage(tool: .claudeCode, available: true, today: today, rolling5h: rolling,
                     messageCount: messageCount, todayByModel: todayByModel,
                     contextWindow: contextWindow, lastUpdated: now)
}

func legacyCodexRead(dir: URL, calendar: Calendar, now: Date, rollingHours: Double = 5) -> ToolUsage {
    guard directoryExists(dir) else { return ToolUsage(tool: .codex, available: false, lastUpdated: now) }
    let windows = DateWindows(now: now, calendar: calendar, rollingHours: rollingHours)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var today = TokenBreakdown(), rolling = TokenBreakdown()
    var messageCount = 0
    var latestTimestamp: Date?
    var latestContextUsed = 0, latestWindow = 0
    for file in jsonlFiles(in: dir) {
        if modificationDate(of: file) < windows.earliestRelevant { continue }
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = rawLine.data(using: .utf8),
                  let line = try? decoder.decode(LCodexLine.self, from: data),
                  let tsString = line.timestamp,
                  let timestamp = parseISOTimestamp(tsString) else { continue }
            let kind = line.payload?.type ?? line.type
            let isToday = windows.isToday(timestamp)
            switch kind {
            case "token_count":
                guard let info = line.payload?.info, let delta = info.lastTokenUsage else { continue }
                if isToday { today += delta.breakdown }
                if windows.isInRollingWindow(timestamp) { rolling += delta.breakdown }
                if latestTimestamp == nil || timestamp > latestTimestamp! {
                    latestTimestamp = timestamp
                    latestContextUsed = delta.inputTokens ?? 0
                    latestWindow = info.modelContextWindow ?? 0
                }
            case "agent_message":
                if isToday { messageCount += 1 }
            default: continue
            }
        }
    }
    let cw = (latestTimestamp != nil && latestWindow > 0)
        ? ContextWindow(used: latestContextUsed, total: latestWindow) : nil
    return ToolUsage(tool: .codex, available: true, today: today, rolling5h: rolling,
                     messageCount: messageCount, contextWindow: cw, lastUpdated: now)
}

// MARK: - Fixtures / helpers

private func claudeLine(_ ts: Date, id: String?, req: String = "r", input: Int, output: Int = 1,
                        cc: Int = 0, cr: Int = 0, model: String = "claude-test",
                        filler: String = "") -> String {
    let idPart = id.map { "\"id\":\"\($0)\"," } ?? ""
    return "{\"type\":\"assistant\",\"timestamp\":\"\(iso(ts))\",\"requestId\":\"\(req)\",\"note\":\"\(filler)\",\"message\":{\(idPart)\"model\":\"\(model)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cache_creation_input_tokens\":\(cc),\"cache_read_input_tokens\":\(cr)}}}"
}

private func codexToken(_ ts: Date, input: Int, cached: Int = 0, output: Int = 1, window: Int = 272_000) -> String {
    "{\"timestamp\":\"\(iso(ts))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"model_context_window\":\(window),\"last_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(input + output)},\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(input + output)}}}}"
}

private func codexMessage(_ ts: Date, text: String = "hi") -> String {
    "{\"timestamp\":\"\(iso(ts))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"message\":\"\(text)\"}}"
}

private func codexTurnContext(_ ts: Date, model: String) -> String {
    "{\"timestamp\":\"\(iso(ts))\",\"type\":\"turn_context\",\"payload\":{\"model\":\"\(model)\"}}"
}

private func append(_ text: String, to file: URL) throws {
    let h = try FileHandle(forWritingTo: file)
    defer { try? h.close() }
    try h.seekToEnd()
    try h.write(contentsOf: Data(text.utf8))
}

final class IncrementalReadingTests: XCTestCase {
    // now = 2026-06-14 10:00 Taipei == 02:00 UTC
    private let now = utc(2026, 6, 14, 2)

    private func claude(_ dir: URL) -> ClaudeCodeReader {
        ClaudeCodeReader(projectsDirectory: dir, calendar: taipeiCalendar, rollingHours: 5)
    }
    private func codex(_ dir: URL) -> CodexReader {
        CodexReader(sessionsDirectory: dir, calendar: taipeiCalendar, rollingHours: 5)
    }

    // A1/A4: equivalence against the legacy algorithm on a multi-file fixture.
    func testClaudeMatchesLegacyOnMultiFileFixture() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let dup = claudeLine(utc(2026, 6, 14, 1), id: "m1", req: "r1", input: 100, cc: 5, cr: 7)
        try writeLines([dup, claudeLine(utc(2026, 6, 13, 20), id: "m2", input: 200),   // today, outside 5h
                        "garbage", "", claudeLine(utc(2026, 6, 13, 10), id: "m3", input: 999)],
                       to: dir.appendingPathComponent("a/s1.jsonl"))
        try writeLines([dup,                                                            // cross-file duplicate
                        claudeLine(utc(2026, 6, 14, 1, 30), id: nil, input: 11, model: "claude-opus-4-8"),
                        claudeLine(utc(2026, 6, 14, 1, 30), id: nil, input: 11, model: "claude-opus-4-8"), // no id: counted twice
                        claudeLine(utc(2026, 6, 14, 1, 30), id: "m4", req: "x", input: 250_000, model: "claude-sonnet-5"),
                        claudeLine(utc(2026, 6, 13, 21, 0), id: "m5", input: 3),        // rolling boundary: exactly 5h before
                        claudeLine(utc(2026, 6, 14, 2, 0, 1), id: "m6", input: 4)],     // after now
                       to: dir.appendingPathComponent("b/s2.jsonl"))
        let r = claude(dir)
        let expected = legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now)
        XCTAssertEqual(try r.read(now: now), expected)
        XCTAssertEqual(try r.read(now: now), expected)   // warm
        XCTAssertGreaterThan(expected.messageCount, 3)
    }

    func testCodexMatchesLegacyOnMultiFileFixture() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeLines([codexMessage(utc(2026, 6, 14, 1)), codexToken(utc(2026, 6, 14, 1), input: 1000, cached: 200),
                        codexToken(utc(2026, 6, 13, 20), input: 50), "oops",
                        codexToken(utc(2026, 6, 13, 10), input: 7, window: 1)],
                       to: dir.appendingPathComponent("2026/06/14/rollout-a.jsonl"))
        try writeLines([codexMessage(utc(2026, 6, 14, 1, 20)), codexToken(utc(2026, 6, 14, 1, 40), input: 5000, window: 400_000)],
                       to: dir.appendingPathComponent("2026/06/14/rollout-b.jsonl"))
        let r = codex(dir)
        let expected = legacyCodexRead(dir: dir, calendar: taipeiCalendar, now: now)
        XCTAssertEqual(try r.read(now: now), expected)
        XCTAssertEqual(try r.read(now: now), expected)
        XCTAssertEqual(expected.contextWindow, ContextWindow(used: 5000, total: 400_000))
    }

    // A3(a)+(e): same cache, append between reads == fresh cache.
    func testClaudeAppendBetweenReadsEqualsFreshRead() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10)], to: f)
        let r = claude(dir)
        _ = try r.read(now: now)
        try append(claudeLine(utc(2026, 6, 14, 1, 10), id: "b", input: 20) + "\n"
                   + claudeLine(utc(2026, 6, 14, 1, 10), id: "a", input: 10) + "\n", to: f)  // b new, a dup
        let warm = try r.read(now: now)
        XCTAssertEqual(warm, try claude(dir).read(now: now))
        XCTAssertEqual(warm, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(warm.today.input, 30)
    }

    func testCodexAppendBetweenReadsEqualsFreshRead() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("2026/06/14/rollout.jsonl")
        try writeLines([codexToken(utc(2026, 6, 14, 1), input: 10)], to: f)
        let r = codex(dir)
        _ = try r.read(now: now)
        try append(codexToken(utc(2026, 6, 14, 1, 30), input: 70, window: 100_000) + "\n"
                   + codexMessage(utc(2026, 6, 14, 1, 31)) + "\n", to: f)
        let warm = try r.read(now: now)
        XCTAssertEqual(warm, try codex(dir).read(now: now))
        XCTAssertEqual(warm.messageCount, 1)
        XCTAssertEqual(warm.contextWindow, ContextWindow(used: 70, total: 100_000))
    }

    // A3(b): unterminated tail is counted when it is complete JSON, not cached, and completing it is correct.
    func testClaudeUnterminatedTailCountedButNotDoubleCounted() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10)], to: f)
        let r = claude(dir)
        XCTAssertEqual(try r.read(now: now).today.input, 10)
        let full = claudeLine(utc(2026, 6, 14, 1, 5), id: "b", input: 20)
        try append(full, to: f)                                  // complete JSON, no newline
        XCTAssertEqual(try r.read(now: now).today.input, 30)
        XCTAssertEqual(try r.read(now: now).today.input, 30)     // re-read tail, still once
        try append("\n", to: f)                                  // now terminated
        XCTAssertEqual(try r.read(now: now).today.input, 30)
        XCTAssertEqual(try r.read(now: now), legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
    }

    func testClaudeHalfWrittenTailIgnoredUntilCompleted() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10)], to: f)
        let r = claude(dir)
        _ = try r.read(now: now)
        let full = claudeLine(utc(2026, 6, 14, 1, 5), id: "b", input: 20)
        let cut = full.index(full.startIndex, offsetBy: full.count / 2)
        try append(String(full[..<cut]), to: f)
        XCTAssertEqual(try r.read(now: now).today.input, 10)
        try append(String(full[cut...]) + "\n", to: f)
        XCTAssertEqual(try r.read(now: now).today.input, 30)
        XCTAssertEqual(try r.read(now: now), legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
    }

    func testCodexUnterminatedTail() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("2026/06/14/rollout.jsonl")
        try writeLines([codexToken(utc(2026, 6, 14, 1), input: 10)], to: f)
        let r = codex(dir)
        _ = try r.read(now: now)
        try append(codexMessage(utc(2026, 6, 14, 1, 5)), to: f)
        XCTAssertEqual(try r.read(now: now).messageCount, 1)
        XCTAssertEqual(try r.read(now: now).messageCount, 1)
        try append("\n", to: f)
        XCTAssertEqual(try r.read(now: now).messageCount, 1)
    }

    // A3(c): truncated / replaced files.
    func testClaudeTruncatedAndReplacedFile() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10, filler: String(repeating: "x", count: 500)),
                        claudeLine(utc(2026, 6, 14, 1, 1), id: "b", input: 20)], to: f)
        let r = claude(dir)
        XCTAssertEqual(try r.read(now: now).today.input, 30)
        // shorter replacement (atomic write: new inode)
        try writeLines([claudeLine(utc(2026, 6, 14, 1, 2), id: "c", input: 5)], to: f)
        XCTAssertEqual(try r.read(now: now).today.input, 5)
        // truncated in place to genuinely shorter, different content (shorter model name)
        let shorter = claudeLine(utc(2026, 6, 14, 1, 3), id: "d", input: 7, model: "m") + "\n"
        let before = (try FileManager.default.attributesOfItem(atPath: f.path)[.size] as! NSNumber).intValue
        XCTAssertLessThan(shorter.utf8.count, before)
        let h = try FileHandle(forWritingTo: f)
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data(shorter.utf8))
        try h.close()
        XCTAssertEqual(try r.read(now: now), legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(try r.read(now: now).today.input, 7)
    }

    func testCodexReplacedWithDifferentContentSameLength() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("2026/06/14/rollout.jsonl")
        try writeLines([codexToken(utc(2026, 6, 14, 1), input: 111)], to: f)
        let r = codex(dir)
        XCTAssertEqual(try r.read(now: now).today.input, 111)
        try writeLines([codexToken(utc(2026, 6, 14, 1), input: 222)], to: f)   // same byte length
        XCTAssertEqual(try r.read(now: now).today.input, 222)
    }

    // A3(d): file ages out of the window -> not counted and evicted from the cache.
    func testAgedOutFileIsDroppedFromCache() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cf = dir.appendingPathComponent("p/s.jsonl")
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10)], to: cf)
        let xdir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: xdir) }
        let xf = xdir.appendingPathComponent("2026/06/14/rollout.jsonl")
        try writeLines([codexToken(utc(2026, 6, 14, 1), input: 10)], to: xf)
        let cr = claude(dir), xr = codex(xdir)
        XCTAssertEqual(try cr.read(now: now).today.input, 10)
        XCTAssertEqual(try xr.read(now: now).today.input, 10)
        XCTAssertEqual(cr.cachedPaths.count, 1)
        XCTAssertEqual(xr.cachedPaths.count, 1)
        let old = utc(2026, 6, 1)
        for f in [cf, xf] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: f.path) }
        XCTAssertEqual(try cr.read(now: now).today.input, 0)
        XCTAssertEqual(try xr.read(now: now).today.input, 0)
        XCTAssertTrue(cr.cachedPaths.isEmpty)
        XCTAssertTrue(xr.cachedPaths.isEmpty)
    }

    // A3(f): multibyte content, including a chunk boundary inside multibyte text.
    func testMultibyteLinesAcrossIncrementalReads() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        let zh = String(repeating: "繁體中文測試😀", count: 40)
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10, filler: zh)], to: f)
        let r = claude(dir)
        XCTAssertEqual(try r.read(now: now).today.input, 10)
        let second = claudeLine(utc(2026, 6, 14, 1, 5), id: "b", input: 20, filler: zh)
        let bytes = Array((second + "\n").utf8)
        let split = bytes.firstIndex(of: 0xE4)! + 1            // inside a 3-byte character
        let h = try FileHandle(forWritingTo: f)
        try h.seekToEnd(); try h.write(contentsOf: Data(bytes[..<split]))
        XCTAssertEqual(try r.read(now: now).today.input, 10)
        try h.write(contentsOf: Data(bytes[split...])); try h.close()
        XCTAssertEqual(try r.read(now: now).today.input, 30)
        XCTAssertEqual(try r.read(now: now), legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))

        let cdir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: cdir) }
        try writeLines([codexMessage(utc(2026, 6, 14, 1), text: zh), codexToken(utc(2026, 6, 14, 1), input: 3)],
                       to: cdir.appendingPathComponent("2026/06/14/rollout.jsonl"))
        let x = codex(cdir)
        XCTAssertEqual(try x.read(now: now), legacyCodexRead(dir: cdir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(try x.read(now: now).messageCount, 1)
    }

    // A3(g): Codex history keeps model attribution after pre-filtering.
    func testCodexHistoryModelAttributionSurvivesPrefilter() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeLines([codexToken(utc(2026, 6, 14, 0, 30), input: 1),                 // before any turn_context: unknown
                        codexTurnContext(utc(2026, 6, 14, 0, 40), model: "gpt-5"),
                        "{\"timestamp\":\"\(iso(utc(2026, 6, 14, 0, 41)))\",\"type\":\"response_item\",\"payload\":{\"type\":\"reasoning\"}}",
                        codexToken(utc(2026, 6, 14, 1), input: 100),
                        codexTurnContext(utc(2026, 6, 14, 1, 10), model: "gpt-5-codex"),
                        codexToken(utc(2026, 6, 14, 1, 20), input: 200),
                        codexMessage(utc(2026, 6, 14, 1, 21))],
                       to: dir.appendingPathComponent("2026/06/14/rollout.jsonl"))
        let range = DateInterval(start: utc(2026, 6, 14), end: utc(2026, 6, 15))
        let h = try codex(dir).history(range: range)
        XCTAssertEqual(h.byModel[ModelKey.unknown.id]?.input, 1)
        XCTAssertEqual(h.byModel[ModelKey(raw: "gpt-5").id]?.input, 100)
        XCTAssertEqual(h.byModel[ModelKey(raw: "gpt-5-codex").id]?.input, 200)
        XCTAssertEqual(h.messageCount, 1)
    }

    func testClaudeHistoryStillDedupsWithPrefilter() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10)
        try writeLines([a, a, "{\"type\":\"user\",\"message\":{\"content\":\"hi\"}}", claudeLine(utc(2026, 6, 14, 2), id: nil, input: 4)],
                       to: dir.appendingPathComponent("p/s.jsonl"))
        let h = try claude(dir).history(range: DateInterval(start: utc(2026, 6, 14), end: utc(2026, 6, 15)))
        XCTAssertEqual(h.messageCount, 2)
        XCTAssertEqual(h.byModel.values.reduce(0) { $0 + $1.input }, 14)
    }

    // Adversarial rewrites: the new content keeps the same head and the same line
    // lengths, so only the cache's own checks (not size/head luck) can catch them.
    private func sameShapeFiles() -> (l1: String, l2: String, x1: String, x2: String, x3: String) {
        (claudeLine(utc(2026, 6, 14, 1, 0), id: "a", input: 10),
         claudeLine(utc(2026, 6, 14, 1, 1), id: "b", input: 20),
         claudeLine(utc(2026, 6, 14, 1, 1), id: "b", input: 90),   // same length as l2
         claudeLine(utc(2026, 6, 14, 1, 2), id: "c", input: 40),
         claudeLine(utc(2026, 6, 14, 1, 3), id: "d", input: 50))
    }

    func testTruncatedToZeroThenGrownPastOldOffset() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        let t = sameShapeFiles()
        try writeLines([t.l1, t.l2], to: f)
        let r = claude(dir)
        XCTAssertEqual(try r.read(now: now).today.input, 30)
        let h = try FileHandle(forWritingTo: f)
        try h.truncate(atOffset: 0); try h.close()
        XCTAssertEqual(try r.read(now: now).today.input, 0)
        // Regrow in place past the old offset with same head and same first two line lengths.
        try append([t.l1, t.x1, t.x2, t.x3].joined(separator: "\n") + "\n", to: f)
        let warm = try r.read(now: now)
        XCTAssertEqual(warm, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(warm.today.input, 10 + 90 + 40 + 50)
    }

    func testInPlaceRewriteLargerWithChangedHead() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        let t = sameShapeFiles()
        try writeLines([t.l1, t.l2], to: f)
        let r = claude(dir)
        _ = try r.read(now: now)
        let h = try FileHandle(forWritingTo: f)           // same inode
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data(([t.x2, t.x3, t.x1, t.l1].joined(separator: "\n") + "\n").utf8))
        try h.close()
        let warm = try r.read(now: now)
        XCTAssertEqual(warm, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(warm.today.input, 40 + 50 + 90 + 10)
    }

    func testInPlaceRewriteLargerSameHeadButDifferentLineBoundary() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        let t = sameShapeFiles()
        try writeLines([t.l1, t.l2], to: f)
        let r = claude(dir)
        _ = try r.read(now: now)
        // Same first line, then a longer, different second line: byte offset-1 is not a newline.
        let longer = claudeLine(utc(2026, 6, 14, 1, 1), id: "b", input: 90, filler: String(repeating: "z", count: 200))
        let h = try FileHandle(forWritingTo: f)
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data(([t.l1, longer, t.x2].joined(separator: "\n") + "\n").utf8))
        try h.close()
        let warm = try r.read(now: now)
        XCTAssertEqual(warm, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(warm.today.input, 10 + 90 + 40)
    }

    func testReplacedByNewInodeAndLarger() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        let t = sameShapeFiles()
        try writeLines([t.l1, t.l2], to: f)
        let r = claude(dir)
        _ = try r.read(now: now)
        try writeLines([t.l1, t.x1, t.x2, t.x3], to: f)   // atomic write: new inode, same head/line shape
        let warm = try r.read(now: now)
        XCTAssertEqual(warm, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        XCTAssertEqual(warm.today.input, 10 + 90 + 40 + 50)
    }

    // Pre-existing coverage gaps in the dedup key and latest tie-break.
    func testDedupKeyIncludesRequestId() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "m", req: "r1", input: 10),
                        claudeLine(utc(2026, 6, 14, 1), id: "m", req: "r2", input: 20),   // same id, other request: kept
                        claudeLine(utc(2026, 6, 14, 1), id: "m", req: "r2", input: 99)],  // exact key repeat: dropped
                       to: dir.appendingPathComponent("p/s.jsonl"))
        let u = try claude(dir).read(now: now)
        XCTAssertEqual(u.today.input, 30)
        XCTAssertEqual(u, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
        let h = try claude(dir).history(range: DateInterval(start: utc(2026, 6, 14), end: utc(2026, 6, 15)))
        XCTAssertEqual(h.byModel.values.reduce(0) { $0 + $1.input }, 30)
    }

    func testLatestTieKeepsFirstSeen() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let ts = utc(2026, 6, 14, 1)
        try writeLines([claudeLine(ts, id: "a", input: 111), claudeLine(ts, id: "b", input: 222)],
                       to: dir.appendingPathComponent("p/s.jsonl"))
        let u = try claude(dir).read(now: now)
        XCTAssertEqual(u.contextWindow?.used, 111)    // `>` keeps the first of equal timestamps
        XCTAssertEqual(u, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
    }

    // Same inode, same size, different bytes: only the mtime tells it changed.
    // (writeLines writes atomically = new inode, so it cannot cover this case.)
    func testSameSizeInPlaceRewriteDetectedByMtime() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 111)], to: f)
        let r = claude(dir)
        XCTAssertEqual(try r.read(now: now).today.input, 111)

        let attrs = try FileManager.default.attributesOfItem(atPath: f.path)
        let inode = attrs[.systemFileNumber] as! NSNumber
        let size = (attrs[.size] as! NSNumber).intValue
        let mtime = attrs[.modificationDate] as! Date
        let rewritten = claudeLine(utc(2026, 6, 14, 1), id: "a", input: 222) + "\n"
        XCTAssertEqual(rewritten.utf8.count, size)
        let h = try FileHandle(forWritingTo: f)
        try h.seek(toOffset: 0)
        try h.write(contentsOf: Data(rewritten.utf8))
        try h.close()
        // Set the mtime explicitly so the test does not depend on timestamp resolution.
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(10)], ofItemAtPath: f.path)
        let after = try FileManager.default.attributesOfItem(atPath: f.path)
        XCTAssertEqual(after[.systemFileNumber] as! NSNumber, inode)
        XCTAssertEqual((after[.size] as! NSNumber).intValue, size)

        let warm = try r.read(now: now)
        XCTAssertEqual(warm.today.input, 222)
        XCTAssertEqual(warm, legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
    }

    // Performance guard: every fallback still gives correct numbers, so only the
    // I/O counters reveal a fast path that silently degrades to full re-reads.
    func testUnchangedFilesAreNotOpenedAndAppendsDigestOnlyNewBytes() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("p/s.jsonl")
        let filler = String(repeating: "x", count: 200)
        try writeLines([claudeLine(utc(2026, 6, 14, 1), id: "a", input: 10, filler: filler),
                        claudeLine(utc(2026, 6, 14, 1, 1), id: "b", input: 20, filler: filler)], to: f)
        let fileSize = { (try! FileManager.default.attributesOfItem(atPath: f.path)[.size] as! NSNumber).intValue }
        let r = claude(dir)

        XCTAssertEqual(try r.read(now: now).today.input, 30)
        XCTAssertEqual(r.cacheStats, IncrementalReadStats(opens: 1, fullDigests: 1, bytesDigested: fileSize()))

        // Unchanged: the hot path must not open the file at all.
        _ = try r.read(now: now)
        _ = try r.read(now: now)
        XCTAssertEqual(r.cacheStats.opens, 1)

        // Appends: one open each, no full re-digest, only the new bytes digested.
        for (i, input) in [40, 80, 160].enumerated() {
            let before = r.cacheStats
            let line = claudeLine(utc(2026, 6, 14, 1, 2 + i), id: "n\(i)", input: input, filler: filler) + "\n"
            try append(line, to: f)
            XCTAssertEqual(try r.read(now: now), legacyClaudeRead(dir: dir, calendar: taipeiCalendar, now: now))
            let after = r.cacheStats
            XCTAssertEqual(after.opens, before.opens + 1, "append \(i)")
            XCTAssertEqual(after.fullDigests, before.fullDigests, "append \(i) must not re-digest from 0")
            XCTAssertEqual(after.bytesDigested - before.bytesDigested, line.utf8.count, "append \(i)")
            // ...and the file is back on the no-I/O hot path afterwards.
            _ = try r.read(now: now)
            XCTAssertEqual(r.cacheStats.opens, after.opens, "after append \(i)")
        }
        XCTAssertEqual(try r.read(now: now).today.input, 10 + 20 + 40 + 80 + 160)
    }

    // A5: real data, opt-in.
    func testRealDataColdVsWarm() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENTMETER_REAL_DATA"] == "1",
                          "set AGENTMETER_REAL_DATA=1 to run against ~/.claude and ~/.codex")
        let fixedNow = Date()
        let c = ClaudeCodeReader(), x = CodexReader()
        let t0 = Date()
        let c1 = try c.read(now: fixedNow), x1 = try x.read(now: fixedNow)
        let t1 = Date()
        let c2 = try c.read(now: fixedNow), x2 = try x.read(now: fixedNow)
        let t2 = Date()
        print("REAL-DATA cold read: \(String(format: "%.3f", t1.timeIntervalSince(t0))) s, warm read: \(String(format: "%.3f", t2.timeIntervalSince(t1))) s")
        print("REAL-DATA claude today total=\(c1.today.total) codex today total=\(x1.today.total) cachedFiles=\(c.cachedPaths.count)+\(x.cachedPaths.count)")
        XCTAssertEqual(c2, c1)
        XCTAssertEqual(x2, x1)
    }
}
