import Foundation
import AgentMeterCore

/// A single value the user can pin to the menu-bar item. Selection is persisted
/// as a CSV of raw values; the bar renders the selected metrics inline.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case claudeTokens
    case claudeFiveHour
    case claudeWeekly
    case claudeContext
    case claudeMessages
    case codexTokens
    case codexContext
    case codexMessages
    case combinedTokens

    var id: String { rawValue }

    /// Whether two selected metrics describe the same thing for different tools
    /// (so a CC/CX prefix is needed to tell them apart).
    enum Kind { case token, context, messages, fiveHour, weekly }
    enum Tool { case claude, codex, combined }

    var kind: Kind {
        switch self {
        case .claudeTokens, .codexTokens, .combinedTokens: return .token
        case .claudeContext, .codexContext:                return .context
        case .claudeMessages, .codexMessages:              return .messages
        case .claudeFiveHour:                              return .fiveHour
        case .claudeWeekly:                                return .weekly
        }
    }

    var tool: Tool {
        switch self {
        case .claudeTokens, .claudeFiveHour, .claudeWeekly, .claudeContext, .claudeMessages:
            return .claude
        case .codexTokens, .codexContext, .codexMessages:
            return .codex
        case .combinedTokens:
            return .combined
        }
    }

    /// Label shown in the Settings multi-select list.
    var settingsTitle: String {
        switch self {
        case .claudeTokens:   return tr("Claude · today tokens", "Claude · 今日 tokens")
        case .claudeFiveHour: return tr("Claude · 5h limit %", "Claude · 5h 額度 %")
        case .claudeWeekly:   return tr("Claude · weekly %", "Claude · 週額度 %")
        case .claudeContext:  return tr("Claude · context %", "Claude · Context %")
        case .claudeMessages: return tr("Claude · messages", "Claude · 訊息數")
        case .codexTokens:    return tr("Codex · today tokens", "Codex · 今日 tokens")
        case .codexContext:   return tr("Codex · context %", "Codex · Context %")
        case .codexMessages:  return tr("Codex · messages", "Codex · 訊息數")
        case .combinedTokens: return tr("Combined · today tokens", "合計 · 今日 tokens")
        }
    }

    /// Short tool prefix used only when the same kind spans both tools.
    private var toolPrefix: String {
        switch tool {
        case .claude:   return "CC"
        case .codex:    return "CX"
        case .combined: return "Σ"
        }
    }

    /// The metric's display value, or nil when there's no data to show.
    @MainActor
    func value(_ store: UsageStore) -> String? {
        switch self {
        case .claudeTokens:
            return tokenString(store.claude)
        case .codexTokens:
            return tokenString(store.codex)
        case .combinedTokens:
            let total = store.combinedTodayBillable
            return total > 0 ? total.compactTokenString : nil
        case .claudeFiveHour:
            return store.claudeQuota.fiveHour.map { "5h \(percent($0.usedPercent))%" }
        case .claudeWeekly:
            return store.claudeQuota.weekly.map { "7d \(percent($0.usedPercent))%" }
        case .claudeContext:
            let cw = store.claudeQuota.contextWindow ?? store.claude.contextWindow
            return cw.map { "ctx \(Int(($0.fraction * 100).rounded()))%" }
        case .codexContext:
            return store.codex.contextWindow.map { "ctx \(Int(($0.fraction * 100).rounded()))%" }
        case .claudeMessages:
            return messageString(store.claude)
        case .codexMessages:
            return messageString(store.codex)
        }
    }

    private func tokenString(_ usage: ToolUsage) -> String? {
        let total = usage.today.billableTotal
        return (usage.available && total > 0) ? total.compactTokenString : nil
    }

    private func messageString(_ usage: ToolUsage) -> String? {
        (usage.available && usage.messageCount > 0) ? "\(usage.messageCount)" : nil
    }

    private func percent(_ p: Double) -> Int { Int(p.rounded()) }

    // MARK: - Bar rendering

    /// Build the inline menu-bar string for the selected metrics (data-less ones hidden).
    @MainActor
    static func barString(_ selected: [MenuBarMetric], store: UsageStore) -> String {
        // A kind needs tool prefixes only when more than one tool's metric of that
        // kind is selected (e.g. Claude tokens AND Codex tokens).
        var toolsByKind: [Kind: Set<Tool>] = [:]
        for m in selected { toolsByKind[m.kind, default: []].insert(m.tool) }

        var parts: [String] = []
        for metric in selected {
            guard let value = metric.value(store) else { continue }
            let needsPrefix = (toolsByKind[metric.kind]?.count ?? 0) > 1
            parts.append(needsPrefix ? "\(metric.toolPrefix) \(value)" : value)
        }
        return parts.joined(separator: "  ")
    }

    // MARK: - Persistence

    static func list(fromCSV csv: String) -> [MenuBarMetric] {
        csv.split(separator: ",").compactMap { MenuBarMetric(rawValue: String($0)) }
    }

    /// Persist in canonical (enum) order, regardless of toggle order.
    static func csv(from set: Set<MenuBarMetric>) -> String {
        allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
}
