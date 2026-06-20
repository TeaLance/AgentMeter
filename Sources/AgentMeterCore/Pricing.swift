import Foundation

/// Per-model USD rates, expressed per 1,000,000 tokens. Cache-read defaults to
/// 0.1× input and cache-write to 1.25× input (Anthropic's published multipliers);
/// reasoning bills at the output rate.
public struct ModelPricing: Sendable, Equatable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheWritePerMTok: Double
    public let cacheReadPerMTok: Double
    public let reasoningPerMTok: Double

    public init(input: Double,
                output: Double,
                cacheWrite: Double? = nil,
                cacheRead: Double? = nil,
                reasoning: Double? = nil) {
        self.inputPerMTok = input
        self.outputPerMTok = output
        self.cacheWritePerMTok = cacheWrite ?? input * 1.25
        self.cacheReadPerMTok = cacheRead ?? input * 0.1
        self.reasoningPerMTok = reasoning ?? output
    }
}

/// A local cost estimate. `isComplete` is false when any tokens belonged to a
/// model with no entry in the pricing table, so the UI can render `≈$X+`.
public struct CostEstimate: Sendable, Equatable {
    public let amountUSD: Double
    public let isComplete: Bool

    public static let zeroComplete = CostEstimate(amountUSD: 0, isComplete: true)

    public static func + (lhs: CostEstimate, rhs: CostEstimate) -> CostEstimate {
        CostEstimate(amountUSD: lhs.amountUSD + rhs.amountUSD,
                     isComplete: lhs.isComplete && rhs.isComplete)
    }
}

/// Built-in pricing table. Anthropic list prices (per the claude-api reference,
/// verified 2026-06); cache/reasoning multipliers applied by `ModelPricing`.
/// OpenAI / Codex models are intentionally absent — add verified rates here to
/// enable their local cost estimate; until then their tokens flip `isComplete`.
public enum PricingTable {
    public static let version = "2026-06"

    public static let builtIn: [String: ModelPricing] = [
        "claude-fable-5":     .init(input: 10, output: 50),
        "claude-mythos-5":    .init(input: 10, output: 50),
        "claude-opus-4-8":    .init(input: 5, output: 25),
        "claude-opus-4-7":    .init(input: 5, output: 25),
        "claude-opus-4-6":    .init(input: 5, output: 25),
        "claude-opus-4-5":    .init(input: 5, output: 25),
        "claude-sonnet-4-6":  .init(input: 3, output: 15),
        "claude-sonnet-4-5":  .init(input: 3, output: 15),
        "claude-haiku-4-5":   .init(input: 1, output: 5),
    ]

    public static func pricing(for key: ModelKey) -> ModelPricing? { builtIn[key.id] }
}

/// Local cost estimate for one model's token breakdown.
public func costEstimate(_ tokens: TokenBreakdown,
                         model: ModelKey,
                         using table: [String: ModelPricing] = PricingTable.builtIn) -> CostEstimate {
    guard let p = table[model.id] else { return CostEstimate(amountUSD: 0, isComplete: false) }
    let usd = (Double(tokens.input) * p.inputPerMTok
               + Double(tokens.output) * p.outputPerMTok
               + Double(tokens.cacheCreation) * p.cacheWritePerMTok
               + Double(tokens.cacheRead) * p.cacheReadPerMTok
               + Double(tokens.reasoning) * p.reasoningPerMTok) / 1_000_000
    return CostEstimate(amountUSD: usd, isComplete: true)
}

/// Sum the cost across a per-model token map (e.g. one day's usage).
public func costEstimate(byModel: [String: TokenBreakdown],
                         using table: [String: ModelPricing] = PricingTable.builtIn) -> CostEstimate {
    byModel.reduce(.zeroComplete) { acc, entry in
        acc + costEstimate(entry.value, model: ModelKey(raw: entry.key), using: table)
    }
}
