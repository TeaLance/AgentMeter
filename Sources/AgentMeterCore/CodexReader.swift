import Foundation

/// Reads OpenAI Codex usage from `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// Each line is `{timestamp, type, payload}`. `payload.type == "token_count"`
/// carries `info.last_token_usage` (the per-turn delta) and `total_token_usage`
/// (cumulative). Daily/rolling totals are summed from the **deltas**, since the
/// cumulative figure would massively over-count.
public struct CodexReader: UsageReader {
    private let sessionsDirectory: URL
    private let calendar: Calendar
    private let rollingHours: Double
    /// Compact rows per file, kept across `read(now:)` calls (copies share it).
    private let cache = IncrementalRowCache<CodexRow>()

    public init(sessionsDirectory: URL, calendar: Calendar = .current, rollingHours: Double = 5) {
        self.sessionsDirectory = sessionsDirectory
        self.calendar = calendar
        self.rollingHours = rollingHours
    }

    /// Convenience initialiser pointing at the real `~/.codex/sessions`.
    public init(calendar: Calendar = .current, rollingHours: Double = 5) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(sessionsDirectory: home.appendingPathComponent(".codex/sessions", isDirectory: true),
                  calendar: calendar, rollingHours: rollingHours)
    }

    public func read(now: Date) throws -> ToolUsage {
        guard directoryExists(sessionsDirectory) else {
            return ToolUsage(tool: .codex, available: false, lastUpdated: now)
        }

        let windows = DateWindows(now: now, calendar: calendar, rollingHours: rollingHours)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var today = TokenBreakdown()
        var rolling = TokenBreakdown()
        var messageCount = 0
        // Track the most-recent token_count for the context-window gauge.
        var latestTimestamp: Date?
        var latestContextUsed = 0
        var latestWindow = 0
        var candidates = Set<String>()

        for file in jsonlFiles(in: sessionsDirectory) {
            if modificationDate(of: file) < windows.earliestRelevant { continue }
            candidates.insert(file.path)

            for row in cache.rows(for: file, parse: { CodexRow.parse($0, decoder: decoder) }) {
                let timestamp = row.timestamp
                let isToday = windows.isToday(timestamp)

                if row.isMessage {
                    if isToday { messageCount += 1 }
                    continue
                }
                if isToday { today += row.breakdown }
                if windows.isInRollingWindow(timestamp) { rolling += row.breakdown }
                if latestTimestamp == nil || timestamp > latestTimestamp! {
                    latestTimestamp = timestamp
                    // Current context fill = this turn's full input prompt (incl cached).
                    latestContextUsed = row.contextUsed
                    latestWindow = row.contextWindow
                }
            }
        }
        cache.retain(only: candidates)

        let contextWindow = (latestTimestamp != nil && latestWindow > 0)
            ? ContextWindow(used: latestContextUsed, total: latestWindow)
            : nil

        return ToolUsage(tool: .codex, available: true,
                         today: today, rolling5h: rolling,
                         messageCount: messageCount, contextWindow: contextWindow,
                         lastUpdated: now)
    }
}

extension CodexReader {
    /// Per-day, per-model usage over `range`. `token_count` lines carry no model,
    /// so we track the latest `turn_context.model` *within each file* and attribute
    /// following deltas to it (`.unknown` if none seen yet). Files are processed
    /// independently and lines kept in file order — never globally sorted.
    public func history(range: DateInterval) throws -> UsageHistory {
        var acc = HistoryAccumulator(tool: .codex, range: range, calendar: calendar)
        guard directoryExists(sessionsDirectory) else { return acc.finish() }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        for file in jsonlFiles(in: sessionsDirectory) {
            if modificationDate(of: file) < range.start { continue }

            var currentModel = ModelKey.unknown.id   // reset per file
            forEachLine(in: file) { bytes in
                // Pre-filter: turn_context is needed to track the model, so it must pass too.
                guard lineContains(bytes, "token_count") || lineContains(bytes, "agent_message")
                        || lineContains(bytes, "turn_context"),
                      let line = try? decoder.decode(CodexLine.self, from: Data(bytes)) else { return }
                let kind = line.payload?.type ?? line.type

                if kind == "turn_context", let m = line.payload?.model {
                    currentModel = ModelKey(raw: m).id
                    return
                }

                guard let tsString = line.timestamp,
                      let timestamp = parseISOTimestamp(tsString),
                      acc.contains(timestamp) else { return }

                switch kind {
                case "token_count":
                    guard let delta = line.payload?.info?.lastTokenUsage else { return }
                    acc.add(delta.breakdown, modelKey: currentModel, at: timestamp)
                case "agent_message":
                    acc.addMessage(at: timestamp)
                default:
                    return
                }
            }
        }
        return acc.finish()
    }
}

// MARK: - Compact row

/// A `token_count` delta or an `agent_message`; the only lines `read(now:)` uses.
struct CodexRow: Sendable {
    let timestamp: Date
    let isMessage: Bool
    let breakdown: TokenBreakdown
    let contextUsed: Int
    let contextWindow: Int

    static func parse(_ bytes: UnsafeRawBufferPointer, decoder: JSONDecoder) -> CodexRow? {
        guard lineContains(bytes, "token_count") || lineContains(bytes, "agent_message"),
              let line = try? decoder.decode(CodexLine.self, from: Data(bytes)),
              let tsString = line.timestamp,
              let timestamp = parseISOTimestamp(tsString) else { return nil }
        switch line.payload?.type ?? line.type {
        case "token_count":
            guard let info = line.payload?.info, let delta = info.lastTokenUsage else { return nil }
            return CodexRow(timestamp: timestamp, isMessage: false, breakdown: delta.breakdown,
                            contextUsed: delta.inputTokens ?? 0, contextWindow: info.modelContextWindow ?? 0)
        case "agent_message":
            return CodexRow(timestamp: timestamp, isMessage: true, breakdown: TokenBreakdown(),
                            contextUsed: 0, contextWindow: 0)
        default:
            return nil
        }
    }
}

extension CodexReader {
    /// File paths currently held by the incremental cache (for tests).
    var cachedPaths: Set<String> { cache.cachedPaths }
    /// I/O counters of the incremental cache (for tests).
    var cacheStats: IncrementalReadStats { cache.ioStats }
}

// MARK: - Rollout line shapes (only the fields we need)

private struct CodexLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let type: String?
    let info: CodexInfo?
    /// Present on `turn_context` lines — the model in use for the turns that follow.
    let model: String?
}

private struct CodexInfo: Decodable {
    let lastTokenUsage: CodexTokenUsage?
    let totalTokenUsage: CodexTokenUsage?
    let modelContextWindow: Int?
}

private struct CodexTokenUsage: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?

    /// Map Codex's accounting into a `TokenBreakdown` whose `total` equals Codex's
    /// `total_tokens`. In Codex, `cached_input_tokens` is a subset of `input_tokens`
    /// and `reasoning_output_tokens` is a subset of `output_tokens`, so we split
    /// them out rather than add, to avoid double-counting.
    var breakdown: TokenBreakdown {
        let cached = cachedInputTokens ?? 0
        let reasoning = reasoningOutputTokens ?? 0
        return TokenBreakdown(
            input: max(0, (inputTokens ?? 0) - cached),
            output: max(0, (outputTokens ?? 0) - reasoning),
            cacheCreation: 0,
            cacheRead: cached,
            reasoning: reasoning
        )
    }
}
