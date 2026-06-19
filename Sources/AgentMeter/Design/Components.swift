import SwiftUI
import AgentMeterCore

/// 1px hairline separator (replaces card shadows for grouping).
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(AM.hairline).frame(height: 1).padding(.horizontal, inset)
    }
}

/// Small rounded-square swatch in a service's identity colour.
struct ServiceSwatch: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color).frame(width: size, height: size)
    }
}

/// Thin status-coloured progress bar (no chunky filled track).
struct ThinBar: View {
    let fraction: Double
    let level: StatusLevel
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AM.track)
                Capsule().fill(statusColor(level))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 3)
    }
}

/// A single aligned metric line: label | thin bar | value (right, status-coloured).
struct MetricRow: View {
    let label: String
    let fraction: Double
    let value: String
    let level: StatusLevel
    var body: some View {
        HStack(spacing: AM.Space.m) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(AM.ink2)
                .frame(width: 60, alignment: .leading)
            ThinBar(fraction: fraction, level: level)
            Text(value)
                .font(.system(size: 12.5)).monospacedDigit()
                .foregroundStyle(statusColor(level))
                .frame(minWidth: 84, alignment: .trailing)
        }
    }
}

/// The big editorial hero number for a service's primary metric.
struct HeroNumber: View {
    let percent: Double
    let label: String
    let level: StatusLevel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 48, weight: .light)).monospacedDigit()
                .tracking(-1)
                .foregroundStyle(statusColor(level))
            Text(label).font(.system(size: 12)).foregroundStyle(AM.ink2)
        }
    }
}

/// Tiny segmented toggle, e.g. [5h | 週], for choosing the hero metric.
struct SegmentedPair: View {
    @Binding var rightSelected: Bool
    let leftLabel: String
    let rightLabel: String
    var body: some View {
        HStack(spacing: 0) {
            seg(leftLabel, active: !rightSelected) { rightSelected = false }
            seg(rightLabel, active: rightSelected) { rightSelected = true }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AM.hairline, lineWidth: 1))
    }

    private func seg(_ text: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10.5))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(active ? AM.paper : AM.ink2)
                .background(active ? AM.ink : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
