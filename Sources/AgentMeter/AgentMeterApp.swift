import SwiftUI
import AppKit
import AgentMeterCore

@main
struct AgentMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

/// The menu-bar item: renders the user-selected metrics inline (data-less ones
/// hidden), or a gauge icon when nothing is available.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage(SettingsKeys.menuBarMetrics) private var metricsCSV = defaultMenuBarMetricsCSV

    var body: some View {
        let text = MenuBarMetric.barString(MenuBarMetric.list(fromCSV: metricsCSV), store: store)
        if text.isEmpty {
            Image(systemName: "gauge.with.dots.needle.33percent")
        } else {
            Text(text)
        }
    }
}

/// Hides the Dock icon so the app lives only in the menu bar, even when launched
/// as a bare binary during development (the bundled .app also sets LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // After the Settings window is dismissed (app loses focus), drop the Dock
        // icon again so we stay a menu-bar-only app.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
