import SwiftUI
import AppKit
import AgentMeterCore

@main
struct AgentMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore.shared
    @StateObject private var lang = LanguageStore.shared
    @StateObject private var colors = ServiceColorStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
                .environmentObject(lang)
                .environmentObject(colors)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar item: renders the user-selected metrics inline (data-less ones
/// hidden), or a gauge icon when nothing is available.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage(SettingsKeys.menuBarMetrics) private var metricsCSV = defaultMenuBarMetricsCSV
    // Re-render when these settings change (render reads them).
    @AppStorage(SettingsKeys.meterShowsRemaining) private var showRemaining = false
    @AppStorage(SettingsKeys.menuBarOrientation) private var orientation = "vertical"
    @AppStorage(SettingsKeys.menuBarShowIcon) private var showIcon = true

    var body: some View {
        let cells = MenuBarMetric.cells(MenuBarMetric.list(fromCSV: metricsCSV), store: store)
        if cells.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            // SwiftUI multi-line labels get clipped to the menu-bar height, so draw
            // the label ourselves into a template image the system scales to fit.
            Image(nsImage: MenuBarLabel.render(cells, horizontal: orientation == "horizontal", showIcon: showIcon))
        }
    }

    private enum Item { case icon(AgentTool); case cell(top: NSAttributedString, bot: NSAttributedString) }

    /// Render the metric cells as a template image. Each service group is preceded
    /// by its logo; cells are stacked (vertical) or inline (horizontal).
    static func render(_ cells: [(tool: AgentTool?, top: String, bottom: String)], horizontal: Bool, showIcon: Bool = true) -> NSImage {
        // Horizontal: label and value share one size so the row is a single height.
        // Vertical: a smaller label sits above the bold value.
        let topFont: NSFont, botFont: NSFont
        if horizontal {
            topFont = NSFont.systemFont(ofSize: 13, weight: .regular)
            botFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        } else {
            topFont = NSFont.systemFont(ofSize: 8, weight: .regular)
            botFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        }
        let cellGap: CGFloat = 8, iconGap: CGFloat = 4, inlineGap: CGFloat = 3
        let attrs: (NSFont) -> [NSAttributedString.Key: Any] = { [.font: $0, .foregroundColor: NSColor.black] }

        // Baseline-relative line metrics (descender is negative → flip to a magnitude).
        let topAsc = topFont.ascender, topDesc = -topFont.descender
        let botAsc = botFont.ascender, botDesc = -botFont.descender
        let botLineH = botAsc + botDesc
        let height = ceil(horizontal ? max(topAsc, botAsc) + max(topDesc, botDesc)
                                     : botLineH + topAsc + topDesc)
        // Logo matches the text height (horizontal) or spans both lines a bit smaller
        // (vertical). Centered vertically in the cell.
        let iconSide = round(height * (horizontal ? 0.92 : 0.62))
        let iconY = round((height - iconSide) / 2)

        // Lay out icons + cells with per-item leading gaps.
        var items: [(item: Item, width: CGFloat, gap: CGFloat)] = []
        var lastTool: AgentTool?
        for c in cells {
            let topA = NSAttributedString(string: c.top, attributes: attrs(topFont))
            let botA = NSAttributedString(string: c.bottom, attributes: attrs(botFont))
            if showIcon, let t = c.tool, t != lastTool {
                items.append((.icon(t), iconSide, items.isEmpty ? 0 : cellGap))
                lastTool = t
            }
            let precededByIcon = items.last.map { if case .icon = $0.item { return true } else { return false } } ?? false
            let topW = topA.size().width
            let lead = topW > 0 ? topW + inlineGap : 0   // drop the gap when there's no label
            let w = horizontal ? ceil(lead + botA.size().width)
                               : ceil(max(topW, botA.size().width))
            items.append((.cell(top: topA, bot: botA), w, items.isEmpty ? 0 : (precededByIcon ? iconGap : cellGap)))
            if c.tool == nil { lastTool = nil }
        }

        let totalW = items.reduce(0) { $0 + $1.gap + $1.width }
        let image = NSImage(size: NSSize(width: max(1, ceil(totalW)), height: max(1, height)))
        image.lockFocus()
        // Shared baseline (distance from image bottom) so label and value sit on one line.
        let baseline = max(topDesc, botDesc)
        var x: CGFloat = 0
        for entry in items {
            x += entry.gap
            switch entry.item {
            case .icon(let tool):
                MenuBarIcon.draw(tool, side: iconSide, origin: NSPoint(x: x, y: iconY))
            case .cell(let topA, let botA):
                let topW = topA.size().width
                if horizontal {
                    if topW > 0 { topA.draw(at: NSPoint(x: x, y: baseline - topDesc)) }
                    let valX = x + (topW > 0 ? topW + inlineGap : 0)
                    botA.draw(at: NSPoint(x: valX, y: baseline - botDesc))
                } else {
                    botA.draw(at: NSPoint(x: x + (entry.width - botA.size().width) / 2, y: 0))
                    if topW > 0 { topA.draw(at: NSPoint(x: x + (entry.width - topW) / 2, y: botLineH)) }
                }
            }
            x += entry.width
        }
        image.unlockFocus()
        image.isTemplate = true   // adapt to light/dark menu bar automatically
        return image
    }
}

/// Hides the Dock icon so the app lives only in the menu bar, even when launched
/// as a bare binary during development (the bundled .app also sets LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FloatingPanelController.shared.refresh()  // restore the HUD if enabled
        // When the app loses focus, drop back to a menu-bar-only app. Resetting the
        // coordinator also clears any window entry whose close we couldn't hook.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ActivationPolicyCoordinator.shared.reset() }
        }
    }
}
