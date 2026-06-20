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

    /// A menu-bar cell rendered as two stacked lines: a short label on top and the
    /// value below (Stats-app style). `label` is the kind tag ("5h"/"ctx"/…) or
    /// empty for token counts (where the tool tag is the top line).
    @MainActor
    func parts(_ store: UsageStore) -> (label: String, value: String)? {
        switch self {
        case .claudeTokens:   return tokenString(store.claude).map { ("", $0) }
        case .codexTokens:    return tokenString(store.codex).map { ("", $0) }
        case .combinedTokens:
            let total = store.combinedTodayTotal
            return total > 0 ? ("", total.compactTokenString) : nil
        case .claudeFiveHour: return store.claudeQuota.fiveHour.map { ("5h", "\(percent($0.usedPercent))%") }
        case .claudeWeekly:   return store.claudeQuota.weekly.map { ("7d", "\(percent($0.usedPercent))%") }
        case .claudeContext:
            let cw = store.claudeQuota.contextWindow ?? store.claude.contextWindow
            return cw.map { ("ctx", "\(Int(($0.fraction * 100).rounded()))%") }
        case .codexContext:
            return store.codex.contextWindow.map { ("ctx", "\(Int(($0.fraction * 100).rounded()))%") }
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

    private func percent(_ p: Double) -> Int { Int(p.rounded()) }

    // MARK: - Cell rendering

    /// Build stacked (top, bottom) cells for the selected metrics; data-less ones
    /// are hidden. Tool prefix is added to the top line only when the same kind
    /// spans both tools (so they can be told apart).
    @MainActor
    static func cells(_ selected: [MenuBarMetric], store: UsageStore) -> [(top: String, bottom: String)] {
        var toolsByKind: [Kind: Set<Tool>] = [:]
        for m in selected { toolsByKind[m.kind, default: []].insert(m.tool) }

        var out: [(String, String)] = []
        for m in selected {
            guard let pv = m.parts(store) else { continue }
            let needsPrefix = (toolsByKind[m.kind]?.count ?? 0) > 1
            let top: String
            if pv.label.isEmpty {
                top = m.toolPrefix                                   // tokens: tool tag identifies it
            } else {
                top = needsPrefix ? "\(m.toolPrefix) \(pv.label)" : pv.label
            }
            out.append((top, pv.value))
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
