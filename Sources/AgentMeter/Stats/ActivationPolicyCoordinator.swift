import AppKit

/// Single owner of the app's activation policy. A menu-bar-only (.accessory) app
/// must briefly become .regular to show a real focusable window (Stats / Settings).
/// Each window `enter()`s on show; windows we own `leave()` on close. The whole
/// count resets to .accessory when the app deactivates, so a never-decremented
/// entry (the SwiftUI Settings scene, whose close we can't hook) self-heals.
@MainActor
final class ActivationPolicyCoordinator {
    static let shared = ActivationPolicyCoordinator()
    private var count = 0

    func enter() { count += 1; apply() }
    func leave() { count = max(0, count - 1); apply() }
    func reset() { count = 0; apply() }

    private func apply() {
        NSApp.setActivationPolicy(count > 0 ? .regular : .accessory)
        if count > 0 { NSApp.activate(ignoringOtherApps: true) }
    }
}
