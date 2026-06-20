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

    var body: some View {
        let cells = MenuBarMetric.cells(MenuBarMetric.list(fromCSV: metricsCSV), store: store)
        if cells.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            HStack(spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    VStack(spacing: 0) {
                        Text(c.top).font(.system(size: 8))
                        Text(c.bottom).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    }
                }
            }
        }
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
