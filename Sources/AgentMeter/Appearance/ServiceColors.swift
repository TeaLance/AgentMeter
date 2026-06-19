import SwiftUI
import AgentMeterCore

/// Per-service identity colour (used for the menu-bar icon, the swatch, the
/// floating ring frame, and the stats chart series). NEVER used for status —
/// status stays on the 4-state ramp in `DesignSystem`.
@MainActor
final class ServiceColorStore: ObservableObject {
    enum Key {
        static let claude = "serviceColorClaude"
        static let codex = "serviceColorCodex"
    }
    /// Brand defaults (also offered as presets alongside a neutral mono option).
    static let claudeBrand = "#D97757"
    static let codexBrand = "#6C6C70"
    static let mono = "#8A857A"

    @Published var claudeHex: String { didSet { persist(claudeHex, Key.claude) } }
    @Published var codexHex: String { didSet { persist(codexHex, Key.codex) } }

    init() {
        let d = UserDefaults.standard
        claudeHex = d.string(forKey: Key.claude) ?? Self.claudeBrand
        codexHex = d.string(forKey: Key.codex) ?? Self.codexBrand
    }

    func color(for tool: AgentTool) -> Color {
        switch tool {
        case .claudeCode: return Color(amHex: claudeHex, fallback: Color(amHex: Self.claudeBrand))
        case .codex:      return Color(amHex: codexHex, fallback: Color(amHex: Self.codexBrand))
        }
    }

    func hex(for tool: AgentTool) -> String {
        tool == .claudeCode ? claudeHex : codexHex
    }

    func setHex(_ hex: String, for tool: AgentTool) {
        if tool == .claudeCode { claudeHex = hex } else { codexHex = hex }
    }

    private func persist(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
