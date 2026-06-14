import SwiftUI
import AgentMeterCore

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(SettingsKeys.showClaude) private var showClaude = true
    @AppStorage(SettingsKeys.showCodex) private var showCodex = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AgentMeter").font(.headline)
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            if showClaude {
                ToolSectionView(usage: store.claude)
            }
            if showCodex {
                if showClaude { Divider() }
                ToolSectionView(usage: store.codex)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("立即更新") { store.refreshNow() }
                Spacer()
                Button("設定…") { openSettingsWindow() }
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private var lastUpdatedText: String {
        guard let date = store.lastRefresh else { return "尚未更新" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "最後更新：\(f.string(from: date))"
    }
}

/// One tool's block: headline today usage + breakdown + messages + rolling 5h.
struct ToolSectionView: View {
    let usage: ToolUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(usage.tool.displayName).font(.subheadline).bold()
                Spacer()
                Circle()
                    .fill(usage.available ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }

            if usage.available {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(usage.today.billableTotal.compactTokenString)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("今日 tokens").font(.caption).foregroundStyle(.secondary)
                }
                breakdownGrid
                HStack(spacing: 16) {
                    metric("訊息", "\(usage.messageCount)")
                    metric("近 5h（估計）", usage.rolling5h.billableTotal.compactTokenString)
                }
                .padding(.top, 2)
            } else {
                Text("未偵測到使用資料")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var breakdownGrid: some View {
        HStack(spacing: 14) {
            breakdownItem("輸入", usage.today.input)
            breakdownItem("輸出", usage.today.output)
            breakdownItem("快取寫", usage.today.cacheCreation)
            breakdownItem("快取讀", usage.today.cacheRead)
        }
        .font(.caption2)
    }

    private func breakdownItem(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value.formatted(.number))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).bold()
        }
    }
}
