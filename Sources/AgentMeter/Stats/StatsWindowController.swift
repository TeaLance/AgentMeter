import AppKit
import SwiftUI

/// Owns the single Stats window (an AppKit `NSWindow` hosting SwiftUI). Opening
/// from a `.accessory` app requires going `.regular` via the coordinator.
@MainActor
final class StatsWindowController: NSObject, NSWindowDelegate {
    static let shared = StatsWindowController()
    private var window: NSWindow?
    private let nav = MainWindowModel()

    func show(tab: MainTab) {
        nav.tab = tab
        if window == nil {
            let root = MainWindowRootView()
                .environmentObject(UsageStore.shared)
                .environmentObject(LanguageStore.shared)
                .environmentObject(ServiceColorStore.shared)
                .environmentObject(nav)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "AgentMeter"
            window.contentView = NSHostingView(rootView: root)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("AgentMeterMain")
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
