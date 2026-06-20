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
    case codexFiveHour
    case codexWeekly
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
        case .claudeFiveHour, .codexFiveHour:              return .fiveHour
        case .claudeWeekly, .codexWeekly:                  return .weekly
        }
    }

    var tool: Tool {
        switch self {
        case .claudeTokens, .claudeFiveHour, .claudeWeekly, .claudeContext, .claudeMessages:
            return .claude
        case .codexTokens, .codexFiveHour, .codexWeekly, .codexContext, .codexMessages:
            return .codex
        case .combinedTokens:
            return .combined
        }
    }

    /// The service whose logo precedes this cell in the menu bar (nil for combined).
    var agentTool: AgentTool? {
        switch tool {
        case .claude:   return .claudeCode
        case .codex:    return .codex
        case .combined: return nil
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
        case .codexFiveHour:  return tr("Codex · 5h limit %", "Codex · 5h 額度 %")
        case .codexWeekly:    return tr("Codex · weekly %", "Codex · 週額度 %")
        case .codexContext:   return tr("Codex · context %", "Codex · Context %")
        case .codexMessages:  return tr("Codex · messages", "Codex · 訊息數")
        case .combinedTokens: return tr("Combined · today tokens", "合計 · 今日 tokens")
        }
    }

    /// A menu-bar cell rendered as two stacked lines: a short label on top and the
    /// value below (Stats-app style). `label` is the kind tag ("5h"/"ctx"/…) or
    /// empty for token counts (where the tool tag is the top line).
    @MainActor
    func parts(_ store: UsageStore) -> (label: String, value: String)? {
        // Honor the used/remaining display setting for percentage metrics.
        let remaining = UserDefaults.standard.bool(forKey: SettingsKeys.meterShowsRemaining)
        func pct(_ used: Double) -> String { "\(Int((remaining ? max(0, 100 - used) : used).rounded()))%" }

        switch self {
        case .claudeTokens:   return tokenString(store.claude).map { ("", $0) }
        case .codexTokens:    return tokenString(store.codex).map { ("", $0) }
        case .combinedTokens:
            let total = store.combinedTodayTotal
            return total > 0 ? ("", total.compactTokenString) : nil
        case .claudeFiveHour: return store.claudeQuota.fiveHour.map { ("5h", pct($0.usedPercent)) }
        case .claudeWeekly:   return store.claudeQuota.weekly.map { ("7d", pct($0.usedPercent)) }
        case .codexFiveHour:  return store.codexFiveHour.map { ("5h", pct($0.usedPercent)) }
        case .codexWeekly:    return store.codexWeekly.map { ("7d", pct($0.usedPercent)) }
        case .claudeContext:
            let cw = store.claudeQuota.contextWindow ?? store.claude.contextWindow
            return cw.map { ("ctx", pct($0.fraction * 100)) }
        case .codexContext:
            return store.codex.contextWindow.map { ("ctx", pct($0.fraction * 100)) }
        case .claudeMessages: return messageString(store.claude).map { ("msg", $0) }
        case .codexMessages:  return messageString(store.codex).map { ("msg", $0) }
        }
    }

    private func tokenString(_ usage: ToolUsage) -> String? {
        let total = usage.today.total
        return (usage.available && total > 0) ? total.compactTokenString : nil
    }

    private func messageString(_ usage: ToolUsage) -> String? {
        (usage.available && usage.messageCount > 0) ? "\(usage.messageCount)" : nil
    }

    // MARK: - Cell rendering

    /// Build (tool, top, bottom) cells for the selected metrics; data-less ones are
    /// hidden. The per-service logo identifies Claude vs Codex, so no text prefix is
    /// added; token cells (which have no kind label) carry "Σ" only for the combined
    /// total, which has no logo of its own.
    @MainActor
    static func cells(_ selected: [MenuBarMetric], store: UsageStore) -> [(tool: AgentTool?, top: String, bottom: String)] {
        var out: [(AgentTool?, String, String)] = []
        for m in selected {
            guard let pv = m.parts(store) else { continue }
            let top = pv.label.isEmpty ? (m.tool == .combined ? "Σ" : "") : pv.label
            out.append((m.agentTool, top, pv.value))
        }
        return out
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
