import SwiftUI
import AppKit
import AgentMeterCore

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(SettingsKeys.showClaude) private var showClaude = true
    @AppStorage(SettingsKeys.showCodex) private var showCodex = true
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AgentMeter").font(.headline)
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small) }
            }

            if showClaude { claudeSection }
            if showCodex {
                if showClaude { Divider() }
                codexSection
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
    }

    // MARK: Claude

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Claude Code", available: store.claude.available)

            if store.claude.available {
                // Prefer the authoritative context window from the bridge; fall back
                // to the transcript-derived one.
                if let cw = store.claudeQuota.contextWindow ?? store.claude.contextWindow {
                    MeterBar(title: "Context window",
                             valueText: contextValue(cw, percent: store.claudeQuota.contextPercent),
                             fraction: cw.fraction)
                }

                if store.claudeQuota.available, store.claudeQuota.fiveHour != nil || store.claudeQuota.weekly != nil {
                    if let fh = store.claudeQuota.fiveHour {
                        MeterBar(title: "5-hour limit", valueText: quotaValue(fh), fraction: fh.usedPercent / 100)
                    }
                    if let wk = store.claudeQuota.weekly {
                        MeterBar(title: "Weekly · all models", valueText: quotaValue(wk), fraction: wk.usedPercent / 100)
                    }
                } else {
                    Button {
                        openSettingsWindow()
                    } label: {
                        Label("啟用即時額度顯示 5h／每週 %", systemImage: "bolt.horizontal.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }

                secondaryMetrics(store.claude)
            } else {
                Text("未偵測到使用資料").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Codex

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Codex", available: store.codex.available)
            if store.codex.available {
                if let cw = store.codex.contextWindow {
                    MeterBar(title: "Context window", valueText: contextValue(cw), fraction: cw.fraction)
                }
                secondaryMetrics(store.codex)
            } else {
                Text("未偵測到使用資料").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ name: String, available: Bool) -> some View {
        HStack {
            Text(name).font(.subheadline).bold()
            Spacer()
            Circle()
                .fill(available ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
        }
    }

    private func secondaryMetrics(_ usage: ToolUsage) -> some View {
        HStack(spacing: 18) {
            metric("今日 tokens", usage.today.billableTotal.compactTokenString)
            metric("訊息", "\(usage.messageCount)")
            metric("近 5h（估計）", usage.rolling5h.billableTotal.compactTokenString)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).bold()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lastUpdatedText).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("立即更新") { store.refreshNow() }
                Spacer()
                Button("設定…") { openSettingsWindow() }
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    // MARK: Formatting

    private func contextValue(_ cw: ContextWindow, percent: Double? = nil) -> String {
        let pct = Int((percent ?? cw.fraction * 100).rounded())
        return "\(cw.used.compactTokenString) / \(cw.total.compactTokenString) (\(pct)%)"
    }

    private func quotaValue(_ w: QuotaWindow) -> String {
        let pct = "\(Int(w.usedPercent.rounded()))%"
        if let reset = shortReset(until: w.resetsAt) {
            return "\(pct) · resets \(reset)"
        }
        return pct
    }

    private var lastUpdatedText: String {
        guard let date = store.lastRefresh else { return "尚未更新" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        var text = "最後更新：\(f.string(from: date))"
        if let asOf = store.claudeQuota.asOf {
            text += " · 額度 as of \(f.string(from: asOf))"
        }
        return text
    }

    private func openSettingsWindow() {
        // Becoming a regular app makes the Settings window reliably show and focus
        // from a menu-bar-only (.accessory) app. AppDelegate reverts to .accessory
        // once the window is dismissed.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
