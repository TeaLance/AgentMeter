import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(SettingsKeys.interval) private var interval: Double = 30
    @AppStorage(SettingsKeys.menuBarMetrics) private var metricsCSV = defaultMenuBarMetricsCSV
    @AppStorage(SettingsKeys.showClaude) private var showClaude = true
    @AppStorage(SettingsKeys.showCodex) private var showCodex = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    @State private var bridgeState = StatusLineBridge.shared.state()
    @State private var bridgeError: String?

    var body: some View {
        Form {
            Picker("更新頻率", selection: $interval) {
                ForEach(refreshIntervalOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .onChange(of: interval) { _, newValue in store.setInterval(newValue) }

            Section("選單列顯示內容（可多選）") {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(metric.settingsTitle, isOn: metricBinding(metric))
                }
                Text("沒資料的項目會自動隱藏；全部隱藏時顯示一個小圖示。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("下拉面板") {
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

            Section("即時額度（Claude，實驗性）") {
                Toggle("啟用即時額度（statusLine 橋接）", isOn: bridgeBinding)
                Text(bridgeHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let bridgeError {
                    Text(bridgeError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }

    private func metricBinding(_ metric: MenuBarMetric) -> Binding<Bool> {
        Binding(
            get: { MenuBarMetric.list(fromCSV: metricsCSV).contains(metric) },
            set: { isOn in
                var set = Set(MenuBarMetric.list(fromCSV: metricsCSV))
                if isOn { set.insert(metric) } else { set.remove(metric) }
                metricsCSV = MenuBarMetric.csv(from: set)
            }
        )
    }

    private var bridgeBinding: Binding<Bool> {
        Binding(
            get: { bridgeState == .enabled },
            set: { setBridge($0) }
        )
    }

    private var bridgeHelpText: String {
        switch bridgeState {
        case .enabled:
            return "已啟用。請在 Claude Code 送出一次訊息，5h／每週額度條才會出現。會在 ~/.claude/settings.json 設定 statusLine（已備份原檔）。"
        case .conflict:
            return "偵測到你已有自訂 statusLine，為避免覆蓋而未啟用。可手動整合或先移除既有設定。"
        case .disabled:
            return "啟用後會讀取 Claude Code 傳給 statusLine 的官方資料來顯示真實 5h／每週 %。不連網、不讀 Keychain。"
        }
    }

    private func setBridge(_ enabled: Bool) {
        do {
            if enabled { try StatusLineBridge.shared.enable() }
            else { try StatusLineBridge.shared.disable() }
            bridgeError = nil
        } catch {
            bridgeError = error.localizedDescription
        }
        bridgeState = StatusLineBridge.shared.state()
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
