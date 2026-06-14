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

        for file in jsonlFiles(in: sessionsDirectory) {
            if modificationDate(of: file) < windows.earliestRelevant { continue }
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = rawLine.data(using: .utf8),
                      let line = try? decoder.decode(CodexLine.self, from: data),
                      let tsString = line.timestamp,
                      let timestamp = parseISOTimestamp(tsString) else { continue }

                let kind = line.payload?.type ?? line.type
                let isToday = windows.isToday(timestamp)

                switch kind {
                case "token_count":
                    guard let info = line.payload?.info, let delta = info.lastTokenUsage else { continue }
                    let breakdown = delta.breakdown
                    if isToday { today += breakdown }
                    if windows.isInRollingWindow(timestamp) { rolling += breakdown }
                    if latestTimestamp == nil || timestamp > latestTimestamp! {
                        latestTimestamp = timestamp
                        // Current context fill = this turn's full input prompt (incl cached).
                        latestContextUsed = delta.inputTokens ?? 0
                        latestWindow = info.modelContextWindow ?? 0
                    }
                case "agent_message":
                    if isToday { messageCount += 1 }
                default:
                    continue
                }
            }
        }

        let contextWindow = (latestTimestamp != nil && latestWindow > 0)
            ? ContextWindow(used: latestContextUsed, total: latestWindow)
            : nil

        return ToolUsage(tool: .codex, available: true,
                         today: today, rolling5h: rolling,
                         messageCount: messageCount, contextWindow: contextWindow,
                         lastUpdated: now)
    }
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
