import Foundation

/// Reads Claude Code usage from `~/.claude/projects/**/*.jsonl`.
///
/// Each line is one transcript event; assistant responses carry `message.usage`.
/// Resumed sessions duplicate prior lines, so usage rows are de-duplicated by
/// `(message.id, requestId)` — the same approach `ccusage` uses.
public struct ClaudeCodeReader: UsageReader {
    private let projectsDirectory: URL
    private let calendar: Calendar
    private let rollingHours: Double

    public init(projectsDirectory: URL, calendar: Calendar = .current, rollingHours: Double = 5) {
        self.projectsDirectory = projectsDirectory
        self.calendar = calendar
        self.rollingHours = rollingHours
    }

    /// Convenience initialiser pointing at the real `~/.claude/projects`.
    public init(calendar: Calendar = .current, rollingHours: Double = 5) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(projectsDirectory: home.appendingPathComponent(".claude/projects", isDirectory: true),
                  calendar: calendar, rollingHours: rollingHours)
    }

    public func read(now: Date) throws -> ToolUsage {
        guard directoryExists(projectsDirectory) else {
            return ToolUsage(tool: .claudeCode, available: false, lastUpdated: now)
        }

        let windows = DateWindows(now: now, calendar: calendar, rollingHours: rollingHours)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var today = TokenBreakdown()
        var rolling = TokenBreakdown()
        var messageCount = 0
        var seen = Set<String>()
        // Track the single most-recent assistant turn for the context-window gauge.
        var latestTimestamp: Date?
        var latestContextUsed = 0
        var latestModel: String?

        for file in jsonlFiles(in: projectsDirectory) {
            // A file last touched before any window we care about cannot hold
            // relevant rows (lines are appended in time order).
            if modificationDate(of: file) < windows.earliestRelevant { continue }
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = rawLine.data(using: .utf8),
                      let line = try? decoder.decode(ClaudeLine.self, from: data),
                      let usage = line.message?.usage,
                      let tsString = line.timestamp,
                      let timestamp = parseISOTimestamp(tsString) else { continue }

                // De-duplicate resumed/duplicated rows by (message.id, requestId).
                if let id = line.message?.id {
                    let key = "\(id)|\(line.requestId ?? "")"
                    if !seen.insert(key).inserted { continue }
                }

                let breakdown = TokenBreakdown(
                    input: usage.inputTokens ?? 0,
                    output: usage.outputTokens ?? 0,
                    cacheCreation: usage.cacheCreationInputTokens ?? 0,
                    cacheRead: usage.cacheReadInputTokens ?? 0
                )

                if windows.isToday(timestamp) {
                    today += breakdown
                    messageCount += 1
                }
                if windows.isInRollingWindow(timestamp) {
                    rolling += breakdown
                }

                if latestTimestamp == nil || timestamp > latestTimestamp! {
                    latestTimestamp = timestamp
                    // Context fill = everything fed to the model this turn (input + cache),
                    // excluding the generated output.
                    latestContextUsed = breakdown.input + breakdown.cacheRead + breakdown.cacheCreation
                    latestModel = line.message?.model
                }
            }
        }

        let contextWindow = latestTimestamp.map { _ -> ContextWindow in
            // Transcripts record the model id WITHOUT the [1m] tier suffix, so a
            // context that already exceeds 200k must be a 1M session.
            let tagged = AgentMeterCore.contextWindow(forModelID: latestModel)
            let total = latestContextUsed > 200_000 ? 1_000_000 : tagged
            return ContextWindow(used: latestContextUsed, total: total)
        }

        return ToolUsage(tool: .claudeCode, available: true,
                         today: today, rolling5h: rolling,
                         messageCount: messageCount, contextWindow: contextWindow,
                         lastUpdated: now)
    }
}

// MARK: - Transcript line shapes (only the fields we need)

private struct ClaudeLine: Decodable {
    let timestamp: String?
    let requestId: String?
    let message: ClaudeMessage?
}

private struct ClaudeMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeUsage?
}

private struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}
