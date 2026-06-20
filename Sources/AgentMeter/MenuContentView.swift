import SwiftUI
import AppKit
import AgentMeterCore

/// The dropdown panel: editorial-minimal. Per service, a big "hero" number
/// (Claude defaults to 5-hour, switchable to weekly; Codex shows context% since
/// quota needs the network), aligned mini-rows for the other metrics, and a
/// footer of today's tokens + messages. Hairlines, no cards, tabular numbers.
struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var colors: ServiceColorStore
    @AppStorage(SettingsKeys.showClaude) private var showClaude = true
    @AppStorage(SettingsKeys.showCodex) private var showCodex = true
    @AppStorage(SettingsKeys.heroMetricClaude) private var claudeHeroRaw = ClaudeHero.fiveHour.rawValue

    private var claudeHero: ClaudeHero { ClaudeHero(rawValue: claudeHeroRaw) ?? .fiveHour }

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Space.m) {
            header
            Hairline()
            if showClaude { claudeBlock }
            if showCodex {
                if showClaude { Hairline() }
                codexBlock
            }
        }
        .padding(AM.Space.l)
        .frame(width: 312)
        .background(AM.paper)
        .foregroundStyle(AM.ink)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lang.tr("USAGE", "用量"))
                    .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(AM.ink2)
                Text(updatedText).font(.system(size: 11)).foregroundStyle(AM.ink3)
            }
            Spacer()
            HStack(spacing: 2) {
                if store.isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.7) }
                iconButton("arrow.clockwise") { store.refreshNow() }
                iconButton("chart.bar") { StatsWindowController.shared.show(tab: .stats) }
                iconButton("gearshape") { StatsWindowController.shared.show(tab: .settings) }
                iconButton("power") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12))
                .foregroundStyle(AM.ink2)
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: Claude

    private var claudeBlock: some View {
        VStack(alignment: .leading, spacing: AM.Space.s) {
            serviceHeader(name: "Claude Code", tool: .claudeCode, available: store.claude.available,
                          plan: store.claudeAccount?.plan)
            if store.claude.available {
                claudeBody
                footer(store.claude)
            } else {
                noData
            }
        }
    }

    @ViewBuilder private var claudeBody: some View {
        let q = store.claudeQuota
        let cw = q.contextWindow ?? store.claude.contextWindow
        let ctxPct = q.contextPercent ?? cw.map { $0.fraction * 100 }
        let hasQuota = q.available && (q.fiveHour != nil || q.weekly != nil)

        VStack(alignment: .leading, spacing: AM.Space.m) {
            if hasQuota {
                let useWeekly = (claudeHero == .weekly && q.weekly != nil) || q.fiveHour == nil
                if let hero = useWeekly ? q.weekly : q.fiveHour {
                    HStack(alignment: .top) {
                        heroFromQuota(hero, label: useWeekly ? lang.tr("weekly", "每週額度")
                                                             : lang.tr("5-hour", "5 小時額度"))
                        Spacer()
                        SegmentedPair(
                            rightSelected: Binding(
                                get: { claudeHero == .weekly },
                                set: { claudeHeroRaw = ($0 ? ClaudeHero.weekly : .fiveHour).rawValue }),
                            leftLabel: "5h", rightLabel: lang.tr("Wk", "週"))
                    }
                    ThinBar(fraction: hero.usedPercent / 100, level: .forUsed(percent: hero.usedPercent))
                }
                if let cw, let ctxPct {
                    MetricRow(label: lang.tr("Context", "Context"), fraction: cw.fraction,
                              value: contextMini(cw, ctxPct), level: .forUsed(percent: ctxPct))
                }
                if let other = useWeekly ? q.fiveHour : q.weekly {
                    MetricRow(label: useWeekly ? lang.tr("5-hour", "5 小時") : lang.tr("weekly", "每週"),
                              fraction: other.usedPercent / 100, value: quotaMini(other),
                              level: .forUsed(percent: other.usedPercent))
                }
            } else if let cw, let ctxPct {
                heroFromPercent(ctxPct, label: lang.tr("context", "Context"))
                ThinBar(fraction: cw.fraction, level: .forUsed(percent: ctxPct))
                enableQuotaLink
            } else {
                enableQuotaLink
            }
        }
    }

    private var enableQuotaLink: some View {
        Button { StatsWindowController.shared.show(tab: .settings) } label: {
            Text(lang.tr("Enable live 5h / weekly quota", "啟用即時 5h／每週額度"))
                .font(.system(size: 11))
        }
        .buttonStyle(.link)
    }

    // MARK: Codex

    private var codexBlock: some View {
        VStack(alignment: .leading, spacing: AM.Space.s) {
            serviceHeader(name: "Codex", tool: .codex, available: store.codex.available,
                          plan: store.codexAccount?.plan)
            if store.codex.available {
                codexBody
                footer(store.codex)
            } else {
                noData
            }
        }
    }

    @ViewBuilder private var codexBody: some View {
        let cw = store.codex.contextWindow
        let ctxPct = cw.map { $0.fraction * 100 }
        VStack(alignment: .leading, spacing: AM.Space.m) {
            if let fh = store.codexFiveHour {
                // Real networked 5-hour quota.
                heroFromQuota(fh, label: lang.tr("5-hour", "5 小時額度"))
                ThinBar(fraction: fh.usedPercent / 100, level: .forUsed(percent: fh.usedPercent))
                if let cw, let ctxPct {
                    MetricRow(label: lang.tr("Context", "Context"), fraction: cw.fraction,
                              value: contextMini(cw, ctxPct), level: .forUsed(percent: ctxPct))
                }
                if let wk = store.codexWeekly {
                    MetricRow(label: lang.tr("weekly", "每週"), fraction: wk.usedPercent / 100,
                              value: quotaMini(wk), level: .forUsed(percent: wk.usedPercent))
                }
            } else if let cw, let ctxPct {
                heroFromPercent(ctxPct, label: lang.tr("context", "Context"))
                ThinBar(fraction: cw.fraction, level: .forUsed(percent: ctxPct))
                if !NetworkFeature.codexQuota.isEnabled {
                    Button { StatsWindowController.shared.show(tab: .settings) } label: {
                        Text(lang.tr("Enable live quota (needs internet)", "啟用即時額度(需連網)"))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: Shared pieces

    private func serviceHeader(name: String, tool: AgentTool, available: Bool, plan: String?) -> some View {
        HStack(spacing: AM.Space.s) {
            ServiceSwatch(color: colors.color(for: tool))
            Text(name).font(.system(size: 13.5, weight: .semibold))
            if let plan, !plan.isEmpty {
                Text(plan.capitalized).font(.system(size: 10.5)).foregroundStyle(AM.ink3)
            }
            Spacer()
            Circle()
                .fill(available ? Color(amLight: "#27A35A", dark: "#34C759") : AM.ink3.opacity(0.6))
                .frame(width: 7, height: 7)
        }
    }

    private func heroFromQuota(_ w: QuotaWindow, label: String) -> some View {
        var full = label
        if let r = shortReset(until: w.resetsAt) { full += " · " + lang.tr("resets \(r)", "\(r) 重置") }
        return HeroNumber(percent: w.usedPercent, label: full, level: .forUsed(percent: w.usedPercent))
    }

    private func heroFromPercent(_ pct: Double, label: String) -> some View {
        HeroNumber(percent: pct, label: label, level: .forUsed(percent: pct))
    }

    private func footer(_ u: ToolUsage) -> some View {
        VStack(alignment: .leading, spacing: AM.Space.s) {
            Hairline()
            HStack(spacing: AM.Space.l) {
                footerItem(lang.tr("Today", "今日"), "\(u.today.billableTotal.compactTokenString) tokens")
                footerItem(lang.tr("Messages", "訊息"), "\(u.messageCount)")
                if !u.todayByModel.isEmpty {
                    footerItem("", moneyString(costEstimate(byModel: u.todayByModel)))
                }
                Spacer()
            }
        }
    }

    private func footerItem(_ label: String, _ value: String) -> Text {
        let prefix = label.isEmpty ? Text("") : Text(label + " ").foregroundColor(AM.ink2)
        return (prefix + Text(value).foregroundColor(AM.ink).bold())
            .font(.system(size: 11.5).monospacedDigit())
    }

    private var noData: some View {
        Text(lang.tr("No usage detected", "未偵測到使用資料"))
            .font(.system(size: 11)).foregroundStyle(AM.ink2)
    }

    // MARK: Formatting

    private func contextMini(_ cw: ContextWindow, _ pct: Double) -> String {
        "\(Int(pct.rounded()))% · \(cw.used.compactTokenString)"
    }

    private func quotaMini(_ w: QuotaWindow) -> String {
        let pct = "\(Int(w.usedPercent.rounded()))%"
        if let r = shortReset(until: w.resetsAt) { return "\(pct) · \(r)" }
        return pct
    }

    private var updatedText: String {
        guard let d = store.lastRefresh else { return lang.tr("not updated yet", "尚未更新") }
        let s = max(0, Int(Date().timeIntervalSince(d)))
        let ago = s < 60 ? "\(s)s" : "\(s / 60)m"
        return lang.tr("updated \(ago) ago", "\(ago)前已更新")
    }

}
