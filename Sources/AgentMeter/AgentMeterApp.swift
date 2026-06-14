import SwiftUI
import AppKit
import AgentMeterCore

@main
struct AgentMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()
    @AppStorage(SettingsKeys.labelMode) private var labelModeRaw = MenuBarLabelMode.combined.rawValue

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            // System renders this as the menu-bar item. Image + compact number.
            let img = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                              accessibilityDescription: "Usage")!
            Image(nsImage: img)
            Text(labelText)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }

    private var labelMode: MenuBarLabelMode {
        MenuBarLabelMode(rawValue: labelModeRaw) ?? .combined
    }

    private var labelText: String {
        switch labelMode {
        case .combined: return store.combinedTodayBillable.compactTokenString
        case .claude:   return store.claude.today.billableTotal.compactTokenString
        case .codex:    return store.codex.today.billableTotal.compactTokenString
        }
    }
}

/// Hides the Dock icon so the app lives only in the menu bar, even when launched
/// as a bare binary during development (the bundled .app also sets LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Open the Settings scene from a button, across macOS versions.
@MainActor
func openSettingsWindow() {
    if #available(macOS 14, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    NSApp.activate(ignoringOtherApps: true)
}
