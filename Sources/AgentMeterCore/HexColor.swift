import Foundation

/// Pure string<->RGB conversion for `#RRGGBB` hex colours. The SwiftUI `Color`
/// wrapper lives in the UI layer; this part is here so it can be unit-tested
/// without AppKit.
public enum HexColor {
    /// Parse `#RRGGBB` or `RRGGBB` (case-insensitive) into 0...255 components.
    /// Returns nil for anything that isn't exactly six hex digits.
    public static func rgb(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Int((value >> 16) & 0xFF),
                Int((value >> 8) & 0xFF),
                Int(value & 0xFF))
    }

    /// Format components (clamped to 0...255) as an uppercase `#RRGGBB` string.
    public static func string(r: Int, g: Int, b: Int) -> String {
        func clamp(_ v: Int) -> Int { min(255, max(0, v)) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
