import Foundation

/// Reads the subscription rate-limit snapshot written by the statusLine bridge
/// (`~/.claude/agentmeter-status.json`). The bridge captures the `rate_limits`
/// object Claude Code passes to statusLine commands; we never touch the network
/// or the Keychain.
public struct ClaudeStatusReader {
    private let statusFile: URL

    public init(statusFile: URL) {
        self.statusFile = statusFile
    }

    /// Convenience initialiser pointing at the real `~/.claude/agentmeter-status.json`.
    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(statusFile: home.appendingPathComponent(".claude/agentmeter-status.json"))
    }

    /// Never throws — any missing/invalid file yields an unavailable quota.
    public func read() -> ClaudeQuota {
        guard let data = try? Data(contentsOf: statusFile) else {
            return ClaudeQuota(available: false)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(StatusFile.self, from: data) else {
            return ClaudeQuota(available: false)
        }

        func window(_ w: StatusFile.Window?) -> QuotaWindow? {
            guard let w, let percent = w.usedPercentage else { return nil }
            return QuotaWindow(usedPercent: percent, resetsAt: w.resetsAt?.date)
        }

        var contextWindow: ContextWindow?
        if let cw = file.contextWindow, let used = cw.totalInputTokens,
           let total = cw.maxTokens ?? cw.contextWindowSize, total > 0 {
            contextWindow = ContextWindow(used: used, total: total)
        }

        return ClaudeQuota(
            available: true,
            fiveHour: window(file.rateLimits?.fiveHour),
            weekly: window(file.rateLimits?.sevenDay),
            contextWindow: contextWindow,
            contextPercent: file.contextWindow?.usedPercentage,
            asOf: file.asOf.flatMap(parseISOTimestamp)
        )
    }
}

// MARK: - Bridge file shape

private struct StatusFile: Decodable {
    let asOf: String?
    let rateLimits: RateLimits?
    let contextWindow: ContextWindowRaw?

    struct RateLimits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
    }

    struct Window: Decodable {
        let usedPercentage: Double?
        let resetsAt: FlexibleDate?
    }

    struct ContextWindowRaw: Decodable {
        let usedPercentage: Double?
        let totalInputTokens: Int?
        let maxTokens: Int?
        let contextWindowSize: Int?
    }
}

/// `resets_at` may arrive as an ISO string or an epoch (seconds or milliseconds).
private struct FlexibleDate: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            date = parseISOTimestamp(string)
        } else if let number = try? container.decode(Double.self) {
            let seconds = number > 1_000_000_000_000 ? number / 1000 : number
            date = Date(timeIntervalSince1970: seconds)
        } else {
            date = nil
        }
    }
}
