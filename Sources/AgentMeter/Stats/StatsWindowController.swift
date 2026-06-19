import AppKit
import SwiftUI

/// Owns the single Stats window (an AppKit `NSWindow` hosting SwiftUI). Opening
/// from a `.accessory` app requires going `.regular` via the coordinator.
@MainActor
final class StatsWindowController: NSObject, NSWindowDelegate {
    static let shared = StatsWindowController()
    private var window: NSWindow?

    func show(lang: LanguageStore, colors: ServiceColorStore) {
        if window == nil {
            let root = StatsRootView()
                .environmentObject(lang)
                .environmentObject(colors)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "AgentMeter"
            window.contentView = NSHostingView(rootView: root)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("AgentMeterStats")
            window.center()
            self.window = window
        }
        ActivationPolicyCoordinator.shared.enter()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicyCoordinator.shared.leave()
    }
}
