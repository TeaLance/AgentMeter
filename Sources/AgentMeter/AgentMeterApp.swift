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
    // Re-render when the used/remaining setting changes (parts() reads it).
    @AppStorage(SettingsKeys.meterShowsRemaining) private var showRemaining = false

    var body: some View {
        let cells = MenuBarMetric.cells(MenuBarMetric.list(fromCSV: metricsCSV), store: store)
        if cells.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            // SwiftUI multi-line labels get clipped to the menu-bar height, so draw
            // the stacked label ourselves into a template image the system scales to fit.
            Image(nsImage: MenuBarLabel.render(cells))
        }
    }

    /// Render the metric cells as a 2-line-per-cell template image (label on top,
    /// value below), drawn at natural size so the menu bar scales it down to fit.
    static func render(_ cells: [(top: String, bottom: String)]) -> NSImage {
        let topFont = NSFont.systemFont(ofSize: 8, weight: .regular)
        let botFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let cellGap: CGFloat = 8
        let attrs: (NSFont) -> [NSAttributedString.Key: Any] = {
            [.font: $0, .foregroundColor: NSColor.black]
        }
        let pieces = cells.map { c -> (top: NSAttributedString, bot: NSAttributedString, w: CGFloat) in
            let top = NSAttributedString(string: c.top, attributes: attrs(topFont))
            let bot = NSAttributedString(string: c.bottom, attributes: attrs(botFont))
            return (top, bot, max(top.size().width, bot.size().width))
        }
        let botH = botFont.boundingRectForFont.height
        let topH = topFont.boundingRectForFont.height
        let height = ceil(botH + topH)
        let width = ceil(pieces.reduce(0) { $0 + $1.w } + cellGap * CGFloat(max(0, pieces.count - 1)))

        let image = NSImage(size: NSSize(width: max(1, width), height: max(1, height)))
        image.lockFocus()
        var x: CGFloat = 0
        for p in pieces {
            let ts = p.top.size(), bs = p.bot.size()
            p.bot.draw(at: NSPoint(x: x + (p.w - bs.width) / 2, y: 0))
            p.top.draw(at: NSPoint(x: x + (p.w - ts.width) / 2, y: botH))
            x += p.w + cellGap
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
