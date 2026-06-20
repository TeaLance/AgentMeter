import SwiftUI
import Charts
import AgentMeterCore

// MARK: - Range

enum StatsRange: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }

    func interval(now: Date = Date()) -> DateInterval {
        let end = now.addingTimeInterval(60)
        switch self {
        case .today: return DateInterval(start: Calendar.current.startOfDay(for: now), end: end)
        case .week:  return DateInterval(start: now.addingTimeInterval(-7 * 86400), end: end)
        case .month: return DateInterval(start: now.addingTimeInterval(-30 * 86400), end: end)
        case .all:   return DateInterval(start: Date(timeIntervalSince1970: 0), end: end)
        }
    }
}

// MARK: - View model

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var range: StatsRange = .month { didSet { reload() } }
    @Published private(set) var claude: UsageHistory?
    @Published private(set) var codex: UsageHistory?
    @Published private(set) var isLoading = false

    func reload() {
        isLoading = true
        let interval = range.interval()
        Task.detached(priority: .utility) {
            let c = try? ClaudeCodeReader().history(range: interval)
            let x = try? CodexReader().history(range: interval)
            await MainActor.run {
                self.claude = c
                self.codex = x
                self.isLoading = false
            }
        }
    }
}

// MARK: - Root

enum ServiceFilter: String, CaseIterable, Identifiable { case all, claude, codex; var id: String { rawValue } }
enum StatsPane: String, CaseIterable, Identifiable { case overview, byModel; var id: String { rawValue } }

struct StatsRootView: View {
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var colors: ServiceColorStore
    @StateObject private var vm = StatsViewModel()
    @State private var service: ServiceFilter = .all
    @State private var pane: StatsPane = .overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 156)
            Rectangle().fill(AM.hairline).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AM.paper)
        .foregroundStyle(AM.ink)
        .onAppear { if vm.claude == nil { vm.reload() } }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AM.Space.l) {
            sidebarGroup(lang.tr("Service", "服務")) {
                sidebarRow(lang.tr("All", "全部"), selected: service == .all) { service = .all }
                sidebarRow("Claude", selected: service == .claude) { service = .claude }
                sidebarRow("Codex", selected: service == .codex) { service = .codex }
            }
            sidebarGroup(lang.tr("View", "視圖")) {
                sidebarRow(lang.tr("Overview", "總覽"), selected: pane == .overview) { pane = .overview }
                sidebarRow(lang.tr("By model", "按模型"), selected: pane == .byModel) { pane = .byModel }
            }
            Spacer()
        }
        .padding(AM.Space.m)
    }

    private func sidebarGroup<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 9.5)).tracking(0.4).foregroundStyle(AM.ink3)
                .padding(.leading, 8).padding(.bottom, 2)
            content()
        }
    }

    private func sidebarRow(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AM.ink : AM.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? AM.hairline : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: AM.Space.l) {
            HStack {
                Text(lang.tr("Usage statistics", "用量統計")).font(.system(size: 13, weight: .semibold))
                Spacer()
                rangeTabs
            }
            if pane == .overview { overview } else { byModel }
            Spacer()
        }
        .padding(AM.Space.xl)
    }

    private var rangeTabs: some View {
        HStack(spacing: 2) {
            ForEach(StatsRange.allCases) { r in
                let on = vm.range == r
                Button { vm.range = r } label: {
                    Text(rangeLabel(r)).font(.system(size: 10.5, weight: on ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(on ? AM.paper : AM.ink2)
                        .background(on ? AM.ink : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AM.hairline, lineWidth: 1))
    }

    private func rangeLabel(_ r: StatsRange) -> String {
        switch r {
        case .today: return lang.tr("Today", "今天")
        case .week:  return lang.tr("7d", "7天")
        case .month: return lang.tr("30d", "30天")
        case .all:   return lang.tr("All", "全部")
        }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: AM.Space.xl) {
            HStack(spacing: 34) {
                kpi(lang.tr("Total tokens", "總 tokens"), Int(totalTokens).compactTokenString)
                kpi(lang.tr("Total cost", "總花費"), moneyString(totalCost))
                // ponytail: breakdown only meaningful in .all; otherwise it duplicates Total cost
                if service == .all {
                    kpi("Claude / Codex", "\(moneyString(cost(.claudeCode))) · \(moneyString(cost(.codex)))", small: true)
                }
            }
            Rectangle().fill(AM.hairline).frame(height: 1)
            sectionHeader(lang.tr("Daily usage", "每日用量"))
            dailyChart
        }
    }

    private func kpi(_ label: String, _ value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(AM.ink2)
            Text(value).font(.system(size: small ? 18 : 28, weight: .light)).monospacedDigit().tracking(-0.5)
        }
    }

    private var dailyChart: some View {
        let points = dailyPoints
        return Group {
            if points.isEmpty {
                emptyHint
            } else {
                Chart {
                    ForEach(points, id: \.day) { p in
                        BarMark(x: .value("Day", p.day, unit: .day), y: .value("Claude", p.claude))
                            .foregroundStyle(colors.color(for: .claudeCode))
                        BarMark(x: .value("Day", p.day, unit: .day), y: .value("Codex", p.codex))
                            .foregroundStyle(colors.color(for: .codex))
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 150)
                HStack(spacing: 14) {
                    legendDot(colors.color(for: .claudeCode), "Claude")
                    legendDot(colors.color(for: .codex), "Codex")
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10.5)).foregroundStyle(AM.ink2)
        }
    }

    // MARK: By model

    private var byModel: some View {
        let rows = modelRows
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(lang.tr("By model", "按模型"))
            if rows.isEmpty {
                emptyHint
            } else {
                ForEach(rows) { row in
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(row.color).frame(width: 7, height: 7)
                        Text(row.model).font(.system(size: 12))
                        Spacer()
                        Text("\(row.tokens.compactTokenString) tokens")
                            .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(AM.ink2)
                        Text(moneyString(row.cost)).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                            .frame(width: 76, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .top) { if row.id != rows.first?.id { Rectangle().fill(AM.hairline).frame(height: 1) } }
                }
            }
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).tracking(0.3).foregroundStyle(AM.ink2)
    }

    private var emptyHint: some View {
        Text(lang.tr(vm.isLoading ? "Loading…" : "No usage in this range.",
                     vm.isLoading ? "載入中…" : "此範圍沒有用量。"))
            .font(.system(size: 12)).foregroundStyle(AM.ink3).padding(.vertical, 24)
    }

    // MARK: Derived data

    private var includedHistories: [UsageHistory] {
        switch service {
        case .all:    return [vm.claude, vm.codex].compactMap { $0 }
        case .claude: return [vm.claude].compactMap { $0 }
        case .codex:  return [vm.codex].compactMap { $0 }
        }
    }

    private var totalTokens: Int { includedHistories.reduce(0) { $0 + $1.grandTotal.total } }
    private var totalCost: CostEstimate { includedHistories.reduce(.zeroComplete) { $0 + $1.cost } }
    private func cost(_ tool: AgentTool) -> CostEstimate {
        (tool == .claudeCode ? vm.claude : vm.codex)?.cost ?? .zeroComplete
    }

    private var dailyPoints: [(day: Date, claude: Int, codex: Int)] {
        var byDay: [Date: (Int, Int)] = [:]
        if service != .codex, let c = vm.claude {
            for d in c.days { byDay[d.day, default: (0, 0)].0 += d.total.total }
        }
        if service != .claude, let x = vm.codex {
            for d in x.days { byDay[d.day, default: (0, 0)].1 += d.total.total }
        }
        return byDay.keys.sorted().map { (day: $0, claude: byDay[$0]!.0, codex: byDay[$0]!.1) }
    }

    private struct ModelRow: Identifiable {
        let id: String, model: String, tokens: Int, cost: CostEstimate, color: Color
    }

    private var modelRows: [ModelRow] {
        var rows: [ModelRow] = []
        func add(_ history: UsageHistory?, color: Color) {
            guard let history else { return }
            for (key, bd) in history.byModel {
                rows.append(ModelRow(id: history.tool.rawValue + key, model: key,
                                     tokens: bd.total,
                                     cost: costEstimate(bd, model: ModelKey(raw: key)), color: color))
            }
        }
        if service != .codex { add(vm.claude, color: colors.color(for: .claudeCode)) }
        if service != .claude { add(vm.codex, color: colors.color(for: .codex)) }
        return rows.sorted { $0.tokens > $1.tokens }
    }

}
