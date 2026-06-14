import SwiftUI

/// A labelled progress bar: title on the left, value on the right, a thin fill below.
/// Mirrors the look of Claude Code's `/usage` bars.
struct MeterBar: View {
    let title: String
    let valueText: String
    let fraction: Double

    private var tint: Color {
        switch fraction {
        case ..<0.75: return .blue
        case ..<0.90: return .orange
        default:      return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer()
                Text(valueText).font(.callout).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(tint)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 5)
        }
    }
}

/// Compact "resets in" label: "45m", "2h", "4d". Nil when no reset time is known.
func shortReset(until date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    let seconds = date.timeIntervalSince(now)
    if seconds <= 0 { return "now" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    let hours = Int(seconds / 3600)
    if hours < 24 { return "\(hours)h" }
    return "\(Int(seconds / 86400))d"
}
