import AppKit
import SwiftUI

/// Shows/hides the floating HUD panel. Reads `floatingEnabled` from defaults so
/// both launch and the Settings toggle can call `refresh()`.
@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()
    private var panel: FloatingPanel?

    /// Apply the persisted `floatingEnabled` setting.
    func refresh() {
        UserDefaults.standard.bool(forKey: SettingsKeys.floatingEnabled) ? show() : hide()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.floatingEnabled)
        refresh()
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        panel?.orderFrontRegardless()  // appears without activating the app
    }

    private func hide() { panel?.orderOut(nil) }

    private func makePanel() -> FloatingPanel {
        let root = FloatingHUDView()
            .environmentObject(UsageStore.shared)
            .environmentObject(ServiceColorStore.shared)
        let hosting = NSHostingView(rootView: root)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        if let area = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 24,
                                         y: area.maxY - panel.frame.height - 24))
        }
        return panel
    }
}
