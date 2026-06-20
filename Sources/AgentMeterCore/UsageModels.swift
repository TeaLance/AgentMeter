import Foundation

/// A coding agent whose usage we report.
public enum AgentTool: String, Sendable, CaseIterable {
    case claudeCode
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// Token counts broken down by category. All readers normalise into this shape.
public struct TokenBreakdown: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int
    public var reasoning: Int

    public init(input: Int = 0,
                output: Int = 0,
                cacheCreation: Int = 0,
                cacheRead: Int = 0,
                reasoning: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
        self.reasoning = reasoning
    }

    /// Sum of every component.
    public var total: Int {
        input + output + cacheCreation + cacheRead + reasoning
    }

    /// Everything except cache *reads*. Cache reads are cheap re-reads of prior
    /// context and dwarf the other counts, so this is the more representative
    /// "how much did I use" figure for the menu-bar headline.
    public var billableTotal: Int {
        input + output + cacheCreation + reasoning
    }

    /// Component-wise addition, used to fold many messages into a single total.
    public static func + (lhs: TokenBreakdown, rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(input: lhs.input + rhs.input,
                       output: lhs.output + rhs.output,
                       cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
                       cacheRead: lhs.cacheRead + rhs.cacheRead,
                       reasoning: lhs.reasoning + rhs.reasoning)
    }

    public static func += (lhs: inout TokenBreakdown, rhs: TokenBreakdown) {
        lhs = lhs + rhs
    }
}

/// How full the most-recent session's context window is.
public struct ContextWindow: Equatable, Sendable {
    public var used: Int
    public var total: Int

    public init(used: Int, total: Int) {
        self.used = used
        self.total = total
    }

    /// Used fraction in 0...1 (0 when total is non-positive).
    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(used) / Double(total))
    }
}

/// A subscription rate-limit window (e.g. the 5-hour or weekly limit).
public struct QuotaWindow: Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Claude.ai subscription usage limits, sourced from the statusLine bridge file.
public struct ClaudeQuota: Equatable, Sendable {
    public var available: Bool
    public var fiveHour: QuotaWindow?
    public var weekly: QuotaWindow?
    /// Authoritative context-window fill from Claude Code (when token counts are present).
    public var contextWindow: ContextWindow?
    /// Context-window used percentage, when only a percentage is available.
    public var contextPercent: Double?
    public var asOf: Date?

    public init(available: Bool,
                fiveHour: QuotaWindow? = nil,
                weekly: QuotaWindow? = nil,
                contextWindow: ContextWindow? = nil,
                contextPercent: Double? = nil,
                asOf: Date? = nil) {
        self.available = available
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.contextWindow = contextWindow
        self.contextPercent = contextPercent
        self.asOf = asOf
    }
}

/// A snapshot of one tool's usage at a point in time.
public struct ToolUsage: Equatable, Sendable {
    public var tool: AgentTool
    /// False when the tool's data directory is absent (not installed / never used).
    public var available: Bool
    public var today: TokenBreakdown
    public var rolling5h: TokenBreakdown
    public var messageCount: Int
    /// Today's tokens split by normalized model key (`ModelKey.id`), used for a
    /// per-model local cost estimate. Empty when the reader can't attribute models.
    public var todayByModel: [String: TokenBreakdown]
    /// Fullness of the most-recent session's context window, if known.
    public var contextWindow: ContextWindow?
    public var lastUpdated: Date

    public init(tool: AgentTool,
                available: Bool,
                today: TokenBreakdown = .init(),
                rolling5h: TokenBreakdown = .init(),
                messageCount: Int = 0,
                todayByModel: [String: TokenBreakdown] = [:],
                contextWindow: ContextWindow? = nil,
                lastUpdated: Date = Date(timeIntervalSince1970: 0)) {
        self.tool = tool
        self.available = available
        self.today = today
        self.rolling5h = rolling5h
        self.messageCount = messageCount
        self.todayByModel = todayByModel
        self.contextWindow = contextWindow
        self.lastUpdated = lastUpdated
    }
}
