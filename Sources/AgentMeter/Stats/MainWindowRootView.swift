import SwiftUI

enum MainTab { case stats, settings }

/// Which tab the single main window shows. Owned by StatsWindowController so the
/// menu-bar buttons can switch tabs on an already-open window.
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var tab: MainTab = .stats
}

/// The single app window: cc-bar-style top tabs — 用量統計 ｜ 設定 — so usage stats
/// and settings live in one place (previously two separate windows the user
/// couldn't find).
struct MainWindowRootView: View {
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var nav: MainWindowModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tab(lang.tr("Usage", "用量統計"), .stats)
                tab(lang.tr("Settings", "設定"), .settings)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AM.paper)
            Rectangle().fill(AM.hairline).frame(height: 1)
            Group {
                switch nav.tab {
                case .stats:    StatsRootView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AM.paper)
        .foregroundStyle(AM.ink)
    }

    private func tab(_ label: String, _ value: MainTab) -> some View {
        let on = nav.tab == value
        return Button { nav.tab = value } label: {
            Text(label)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? AM.paper : AM.ink2)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(on ? AM.ink : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
