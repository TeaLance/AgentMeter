import AppKit

/// Always-on-top, non-activating HUD panel. Draggable by its background; snaps to
/// the nearest screen edge on mouse-up when close enough.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        snapToEdge()
    }

    private func snapToEdge(threshold: CGFloat = 26, margin: CGFloat = 10) {
        guard let area = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = frame
        if f.minX - area.minX < threshold { f.origin.x = area.minX + margin }
        else if area.maxX - f.maxX < threshold { f.origin.x = area.maxX - f.width - margin }
        if area.maxY - f.maxY < threshold { f.origin.y = area.maxY - f.height - margin }
        else if f.minY - area.minY < threshold { f.origin.y = area.minY + margin }
        setFrame(f, display: true, animate: true)
    }
}
