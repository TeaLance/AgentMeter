import Foundation

/// One calendar day's usage, split by normalized model key.
public struct DayBucket: Sendable, Equatable {
    public let day: Date            // start-of-day in the query calendar
    public var byModel: [String: TokenBreakdown]
    public var messageCount: Int

    public init(day: Date, byModel: [String: TokenBreakdown] = [:], messageCount: Int = 0) {
        self.day = day
        self.byModel = byModel
        self.messageCount = messageCount
    }

    /// Sum across every model used that day.
    public var total: TokenBreakdown { byModel.values.reduce(TokenBreakdown(), +) }
}

/// Aggregated usage for one tool over a date range — the data the stats window
/// renders (daily chart, by-model table, KPI totals).
public struct UsageHistory: Sendable, Equatable {
    public let tool: AgentTool
    public let range: DateInterval
    /// Ascending by day; sparse (only days with usage appear).
    public var days: [DayBucket]
    /// Whole-range rollup keyed by normalized model id.
    public var byModel: [String: TokenBreakdown]
    public var messageCount: Int

    public init(tool: AgentTool, range: DateInterval,
                days: [DayBucket] = [], byModel: [String: TokenBreakdown] = [:],
                messageCount: Int = 0) {
        self.tool = tool
        self.range = range
        self.days = days
        self.byModel = byModel
        self.messageCount = messageCount
    }

    public var grandTotal: TokenBreakdown { byModel.values.reduce(TokenBreakdown(), +) }

    /// Total local cost estimate across the range (incomplete if any model is unpriced).
    public var cost: CostEstimate { costEstimate(byModel: byModel) }
}

/// Accumulates rows into per-day, per-model buckets. Shared by both readers'
/// `history(range:)` so Claude and Codex bucket identically.
struct HistoryAccumulator {
    let tool: AgentTool
    let range: DateInterval
    let calendar: Calendar
    private var days: [Date: DayBucket] = [:]
    private(set) var byModel: [String: TokenBreakdown] = [:]
    private(set) var messageCount = 0

    init(tool: AgentTool, range: DateInterval, calendar: Calendar) {
        self.tool = tool
        self.range = range
        self.calendar = calendar
    }

    func contains(_ ts: Date) -> Bool { ts >= range.start && ts < range.end }

    mutating func add(_ breakdown: TokenBreakdown, modelKey: String, at ts: Date) {
        let day = calendar.startOfDay(for: ts)
        var bucket = days[day] ?? DayBucket(day: day)
        bucket.byModel[modelKey, default: TokenBreakdown()] += breakdown
        days[day] = bucket
        byModel[modelKey, default: TokenBreakdown()] += breakdown
    }

    mutating func addMessage(at ts: Date) {
        let day = calendar.startOfDay(for: ts)
        var bucket = days[day] ?? DayBucket(day: day)
        bucket.messageCount += 1
        days[day] = bucket
        messageCount += 1
    }

    func finish() -> UsageHistory {
        UsageHistory(tool: tool, range: range,
                     days: days.values.sorted { $0.day < $1.day },
                     byModel: byModel, messageCount: messageCount)
    }
}
