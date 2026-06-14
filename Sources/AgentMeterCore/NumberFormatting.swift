import Foundation

public extension Int {
    /// Compact human form for menu-bar display: 999 -> "999", 1234 -> "1.2K",
    /// 1_500_000 -> "1.5M". Negative values are not expected (token counts).
    var compactTokenString: String {
        let n = Double(self)
        switch abs(self) {
        case 0..<1_000:
            return "\(self)"
        case 1_000..<1_000_000:
            return String(format: "%.1fK", n / 1_000)
        case 1_000_000..<1_000_000_000:
            return String(format: "%.1fM", n / 1_000_000)
        default:
            return String(format: "%.1fB", n / 1_000_000_000)
        }
    }
}
