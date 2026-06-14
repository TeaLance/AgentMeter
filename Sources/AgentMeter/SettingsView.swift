import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(SettingsKeys.interval) private var interval: Double = 30
    @AppStorage(SettingsKeys.labelMode) private var labelModeRaw = MenuBarLabelMode.combined.rawValue
    @AppStorage(SettingsKeys.showClaude) private var showClaude = true
    @AppStorage(SettingsKeys.showCodex) private var showCodex = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("更新頻率", selection: $interval) {
                ForEach(refreshIntervalOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .onChange(of: interval) { _, newValue in store.setInterval(newValue) }

            Picker("選單列顯示", selection: $labelModeRaw) {
                ForEach(MenuBarLabelMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Section {
                Toggle("顯示 Claude Code", isOn: $showClaude)
                Toggle("顯示 Codex", isOn: $showCodex)
            }

            Section {
                Toggle("開機時自動啟動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "設定開機啟動失敗：\(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
