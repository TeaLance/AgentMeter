import SwiftUI
import AppKit
import AgentMeterCore

/// Editorial-minimal design tokens. Deliberately NOT cc-bar's soft-card/gradient
/// look: paper background, ink text, hairline separators (no card shadows),
/// tabular numbers, thin bars. Identity colour (per service) and status colour
/// (by remaining quota) are kept strictly separate.
enum AM {
    static let paper   = Color(amLight: "#FAF9F6", dark: "#1B1A17")
    static let ink     = Color(amLight: "#1A1813", dark: "#ECEAE3")
    static let ink2    = Color(amLight: "#76726A", dark: "#9A958A")
    static let ink3    = Color(amLight: "#A8A395", dark: "#6F6B61")
    static let hairline = Color(amLight: "#EBE7DE", dark: "#33302A")
    static let track   = Color(amLight: "#E7E3D9", dark: "#33302A")

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }
}

/// 4-state status colour, legible on both paper (darker) and dark (brighter).
/// Single source of truth used by every bar / hero number.
func statusColor(_ level: StatusLevel) -> Color {
    switch level {
    case .normal:  return Color(amLight: "#1F8A4C", dark: "#4EC56F")
    case .warning: return Color(amLight: "#A9790F", dark: "#E6C34A")
    case .low:     return Color(amLight: "#C95E16", dark: "#FF8A3D")
    case .empty:   return Color(amLight: "#C9304A", dark: "#FF6B82")
    }
}

func statusColor(forUsed percent: Double) -> Color {
    statusColor(.forUsed(percent: percent))
}

/// Plain money string — no `≈`, no `+`. `$X.XX` when priced; `—` when the cost is
/// entirely unknown (unpriced models), so we never show a misleading `$0.00`.
func moneyString(_ est: CostEstimate) -> String {
    (!est.isComplete && est.amountUSD == 0) ? "—" : "$" + String(format: "%.2f", est.amountUSD)
}

extension Color {
    /// Adaptive sRGB colour from two `#RRGGBB` strings (light / dark appearance).
    init(amLight light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = HexColor.rgb(isDark ? dark : light) ?? (r: 0, g: 0, b: 0)
            return NSColor(srgbRed: CGFloat(c.r) / 255,
                           green: CGFloat(c.g) / 255,
                           blue: CGFloat(c.b) / 255,
                           alpha: 1)
        })
    }

    /// Solid sRGB colour from a single `#RRGGBB` string (used for identity colours).
    init(amHex hex: String, fallback: Color = .secondary) {
        guard let c = HexColor.rgb(hex) else { self = fallback; return }
        self.init(.sRGB,
                  red: Double(c.r) / 255,
                  green: Double(c.g) / 255,
                  blue: Double(c.b) / 255)
    }
}
