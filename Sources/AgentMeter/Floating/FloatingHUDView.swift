import SwiftUI
import AgentMeterCore

/// The dual-ring desktop HUD content. Ring frame = identity colour, arc = status
/// colour, centre = the metric. Dims to the configured idle opacity unless hovered.
struct FloatingHUDView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var colors: ServiceColorStore
    @AppStorage(SettingsKeys.floatingShowClaude) private var showClaude = true
    @AppStorage(SettingsKeys.floatingShowCodex) private var showCodex = true
    @AppStorage(SettingsKeys.floatingIdleOpacity) private var idleOpacity = 0.7
    @AppStorage(SettingsKeys.meterShowsRemaining) private var showRemaining = false
    @State private var hovering = false

    struct Metric { let used: Double; let label: String
        var fraction: Double { used / 100 }
        var pct: String { "\(Int(used.rounded()))%" }
        var level: StatusLevel { .forUsed(percent: used) }
    }

    var body: some View {
        HStack(spacing: 20) {
            if showClaude, let m = claudeMetric { cell(.claudeCode, "Claude", m) }
            if showCodex, let m = codexMetric { cell(.codex, "Codex", m) }
            if visibleCount == 0 {
                Text("AgentMeter").font(.system(size: 11)).foregroundStyle(AM.ink3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AM.hairline, lineWidth: 0.5))
        .foregroundStyle(AM.ink)
        .opacity(hovering ? 1 : idleOpacity)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .fixedSize()
    }

    private func cell(_ tool: AgentTool, _ name: String, _ m: Metric) -> some View {
        let shown = showRemaining ? max(0, 100 - m.used) : m.used
        return VStack(spacing: 5) {
            RingMeter(fraction: shown / 100, level: m.level, percentText: "\(Int(shown.rounded()))%",
                      trackColor: colors.color(for: tool).opacity(0.3))
            HStack(spacing: 4) {
                ServiceSwatch(color: colors.color(for: tool), size: 6)
                Text("\(name) · \(m.label)").font(.system(size: 9.5)).foregroundStyle(AM.ink2)
            }
        }
    }

    private var visibleCount: Int {
        (showClaude && claudeMetric != nil ? 1 : 0) + (showCodex && codexMetric != nil ? 1 : 0)
    }

    private var claudeMetric: Metric? {
        let q = store.claudeQuota
        if let fh = q.fiveHour { return Metric(used: fh.usedPercent, label: "5h") }
        if let cw = q.contextWindow ?? store.claude.contextWindow {
            return Metric(used: q.contextPercent ?? cw.fraction * 100, label: "ctx")
        }
        return nil
    }

    private var codexMetric: Metric? {
        guard let cw = store.codex.contextWindow else { return nil }
        return Metric(used: cw.fraction * 100, label: "ctx")
    }
}
