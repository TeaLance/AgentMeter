import Foundation

/// Tabs of the single main window: usage stats sits alongside the settings panes
/// (one tab bar — no separate stats window / settings window).
enum AppTab: Hashable { case stats, general, appearance, menubar, floating, bridge, advanced }

/// Which tab the window shows. Owned by StatsWindowController so the menu-bar
/// buttons can switch tabs on an already-open window.
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var selection: AppTab = .stats
}
