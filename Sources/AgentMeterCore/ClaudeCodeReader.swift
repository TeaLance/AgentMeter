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
            }
        }

        return ToolUsage(tool: .claudeCode, available: true,
                         today: today, rolling5h: rolling,
                         messageCount: messageCount, lastUpdated: now)
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
    let usage: ClaudeUsage?
}

private struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}
