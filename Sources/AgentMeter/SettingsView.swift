import SwiftUI
import ServiceManagement
import AgentMeterCore

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var colors: ServiceColorStore

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(lang.tr("General", "一般"), systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label(lang.tr("Appearance", "外觀"), systemImage: "paintpalette") }
            MenuBarSettings()
                .tabItem { Label(lang.tr("Menu Bar", "選單列"), systemImage: "menubar.rectangle") }
            BridgeSettings()
                .tabItem { Label(lang.tr("Claude Quota", "Claude 額度"), systemImage: "bolt.horizontal.circle") }
        }
        .frame(width: 440, height: 420)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var lang: LanguageStore
    @AppStorage(SettingsKeys.interval) private var interval: Double = 30
    @AppStorage(SettingsKeys.heroMetricClaude) private var claudeHeroRaw = ClaudeHero.fiveHour.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker(lang.tr("Language", "語言"), selection: $lang.language) {
                Text("繁體中文").tag(AppLanguage.zh)
                Text("English").tag(AppLanguage.en)
            }

            Picker(lang.tr("Refresh interval", "更新頻率"), selection: $interval) {
                ForEach(refreshIntervalSecondsOptions, id: \.self) { s in
                    Text(refreshIntervalLabel(s)).tag(s)
                }
            }
            .onChange(of: interval) { _, v in store.setInterval(v) }

            Picker(lang.tr("Claude hero metric", "Claude 英雄指標"), selection: $claudeHeroRaw) {
                Text(lang.tr("5-hour", "5 小時額度")).tag(ClaudeHero.fiveHour.rawValue)
                Text(lang.tr("Weekly", "每週額度")).tag(ClaudeHero.weekly.rawValue)
            }

            Section {
                Toggle(lang.tr("Launch at login", "開機時自動啟動"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = lang.tr("Couldn't set launch at login: ", "設定開機啟動失敗：") + error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var colors: ServiceColorStore

    var body: some View {
        Form {
            Section(lang.tr("Identity colors", "識別色")) {
                colorRow("Claude Code", tool: .claudeCode,
                         presets: [ServiceColorStore.claudeBrand, ServiceColorStore.mono])
                colorRow("Codex", tool: .codex,
                         presets: [ServiceColorStore.codexBrand, ServiceColorStore.mono])
                Text(lang.tr("Used for the menu-bar icon, swatch, and floating ring. Meter colors follow remaining quota, not this.",
                             "用於選單列 icon、色點與浮動環。量表顏色依剩餘額度，不受此影響。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(lang.tr("Cost is a local estimate (prices as of \(PricingTable.version)).",
                             "花費為本機估算（定價版本 \(PricingTable.version)）。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func colorRow(_ name: String, tool: AgentTool, presets: [String]) -> some View {
        HStack {
            ColorPicker(name, selection: Binding(
                get: { colors.color(for: tool) },
                set: { colors.setHex(hexString(from: $0), for: tool) }))
            Spacer()
            ForEach(presets, id: \.self) { hex in
                Button { colors.setHex(hex, for: tool) } label: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(amHex: hex)).frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Menu Bar

private struct MenuBarSettings: View {
    @EnvironmentObject private var lang: LanguageStore
    @AppStorage(SettingsKeys.menuBarMetrics) private var metricsCSV = defaultMenuBarMetricsCSV
    @AppStorage(SettingsKeys.showClaude) private var showClaude = true
    @AppStorage(SettingsKeys.showCodex) private var showCodex = true

    var body: some View {
        Form {
            Section(lang.tr("Menu-bar metrics (multi-select)", "選單列顯示內容（可多選）")) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(metric.settingsTitle, isOn: metricBinding(metric))
                }
                Text(lang.tr("Metrics with no data are hidden; a small icon shows when all are hidden.",
                             "沒資料的項目會自動隱藏；全部隱藏時顯示一個小圖示。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(lang.tr("Dropdown panel", "下拉面板")) {
                Toggle(lang.tr("Show Claude Code", "顯示 Claude Code"), isOn: $showClaude)
                Toggle(lang.tr("Show Codex", "顯示 Codex"), isOn: $showCodex)
            }
        }
        .formStyle(.grouped)
    }

    private func metricBinding(_ metric: MenuBarMetric) -> Binding<Bool> {
        Binding(
            get: { MenuBarMetric.list(fromCSV: metricsCSV).contains(metric) },
            set: { isOn in
                var set = Set(MenuBarMetric.list(fromCSV: metricsCSV))
                if isOn { set.insert(metric) } else { set.remove(metric) }
                metricsCSV = MenuBarMetric.csv(from: set)
            })
    }
}

// MARK: - Claude quota bridge

private struct BridgeSettings: View {
    @EnvironmentObject private var lang: LanguageStore
    @State private var bridgeState = StatusLineBridge.shared.state()
    @State private var bridgeError: String?

    var body: some View {
        Form {
            Section(lang.tr("Live quota (Claude, experimental)", "即時額度（Claude，實驗性）")) {
                Toggle(lang.tr("Enable live quota (statusLine bridge)", "啟用即時額度（statusLine 橋接）"),
                       isOn: bridgeBinding)
                Text(bridgeHelpText).font(.caption).foregroundStyle(.secondary)
                if let bridgeError {
                    Text(bridgeError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var bridgeBinding: Binding<Bool> {
        Binding(get: { bridgeState == .enabled }, set: { setBridge($0) })
    }

    private var bridgeHelpText: String {
        switch bridgeState {
        case .enabled:
            return lang.tr("Enabled. Send one message in Claude Code for the 5h/weekly bars to appear. Sets statusLine in ~/.claude/settings.json (original backed up).",
                           "已啟用。請在 Claude Code 送出一次訊息，5h／每週額度條才會出現。會在 ~/.claude/settings.json 設定 statusLine（已備份原檔）。")
        case .conflict:
            return lang.tr("Detected an existing custom statusLine, so it wasn't enabled (to avoid overwriting). Integrate manually or remove the existing one first.",
                           "偵測到你已有自訂 statusLine，為避免覆蓋而未啟用。可手動整合或先移除既有設定。")
        case .disabled:
            return lang.tr("When on, reads the official data Claude Code passes to statusLine to show real 5h/weekly %. No network, no Keychain.",
                           "啟用後會讀取 Claude Code 傳給 statusLine 的官方資料來顯示真實 5h／每週 %。不連網、不讀 Keychain。")
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
}
