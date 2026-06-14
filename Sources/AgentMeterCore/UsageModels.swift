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

/// A snapshot of one tool's usage at a point in time.
public struct ToolUsage: Equatable, Sendable {
    public var tool: AgentTool
    /// False when the tool's data directory is absent (not installed / never used).
    public var available: Bool
    public var today: TokenBreakdown
    public var rolling5h: TokenBreakdown
    public var messageCount: Int
    public var lastUpdated: Date

    public init(tool: AgentTool,
                available: Bool,
                today: TokenBreakdown = .init(),
                rolling5h: TokenBreakdown = .init(),
                messageCount: Int = 0,
                lastUpdated: Date = Date(timeIntervalSince1970: 0)) {
        self.tool = tool
        self.available = available
        self.today = today
        self.rolling5h = rolling5h
        self.messageCount = messageCount
        self.lastUpdated = lastUpdated
    }
}
