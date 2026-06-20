import SwiftUI
import ServiceManagement
import AgentMeterCore

/// The single window's content: usage stats + settings panes in one tab bar.
struct RootTabView: View {
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var nav: MainWindowModel

    var body: some View {
        TabView(selection: $nav.selection) {
            StatsRootView()
                .tabItem { Label(lang.tr("Usage", "用量統計"), systemImage: "chart.bar") }
                .tag(AppTab.stats)
            GeneralSettings()
                .tabItem { Label(lang.tr("General", "一般"), systemImage: "gearshape") }
                .tag(AppTab.general)
            AppearanceSettings()
                .tabItem { Label(lang.tr("Appearance", "外觀"), systemImage: "paintpalette") }
                .tag(AppTab.appearance)
            MenuBarSettings()
                .tabItem { Label(lang.tr("Menu Bar", "選單列"), systemImage: "menubar.rectangle") }
                .tag(AppTab.menubar)
            FloatingSettings()
                .tabItem { Label(lang.tr("Floating", "浮動"), systemImage: "macwindow.on.rectangle") }
                .tag(AppTab.floating)
        }
        .background(AM.paper)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var lang: LanguageStore
    @EnvironmentObject private var colors: ServiceColorStore
    @AppStorage(SettingsKeys.interval) private var interval: Double = 30
    @AppStorage(SettingsKeys.meterShowsRemaining) private var meterShowsRemaining = false
    // Live quota / connectivity (default on).
    @AppStorage(SettingsKeys.netCodexQuota) private var codexQuota = true
    @AppStorage(SettingsKeys.showAccounts) private var showAccounts = true
    @State private var pending: NetworkFeature?
    // Claude live quota via the statusLine bridge (local, no network).
    @State private var bridgeState = StatusLineBridge.shared.state()
    @State private var bridgeError: String?
    // Launch at login.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(lang.tr("Accounts", "帳號")) {
                accountRow("Claude Code", provider: "Anthropic", tool: .claudeCode, account: store.claudeAccount)
                accountRow("Codex", provider: "OpenAI", tool: .codex, account: store.codexAccount)
            }

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

            Picker(lang.tr("Meters show", "量表顯示"), selection: $meterShowsRemaining) {
                Text(lang.tr("Used", "已使用")).tag(false)
                Text(lang.tr("Remaining", "剩餘")).tag(true)
            }

            Section(lang.tr("Live quota & connectivity", "即時額度與連線")) {
                featureToggle(.showAccounts)
                claudeLiveQuotaRow
                featureToggle(.codexQuota)
            }

            Section {
                Toggle(lang.tr("Launch at login", "開機時自動啟動"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                    .disabled(!isInstalledApp)
                if isInstalledApp, let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .alert(pending?.title ?? "",
               isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
               presenting: pending) { feature in
            Button(lang.tr("Cancel", "取消"), role: .cancel) {}
            Button(lang.tr("Enable", "啟用")) {
                binding(for: feature).wrappedValue = true
                UsageStore.shared.refreshNow()   // pick up the new data immediately
            }
        } message: { feature in
            Text(feature.explanation)
        }
    }

    // Claude live quota: same row shape as the network toggles, but it reads the
    // local statusLine data Claude Code writes (no network), so its badge says so.
    @ViewBuilder private var claudeLiveQuotaRow: some View {
        Toggle(isOn: Binding(get: { bridgeState == .enabled }, set: { setBridge($0) })) {
            HStack(spacing: 6) {
                Text(lang.tr("Claude live quota", "Claude 即時額度"))
                badge(lang.tr("reads local data", "讀本機資料"), network: false)
            }
        }
        if bridgeState == .conflict {
            Text(lang.tr("Detected an existing custom statusLine, so it wasn't enabled (to avoid overwriting). Remove the existing one first.",
                         "偵測到你已有自訂 statusLine，為避免覆蓋而未啟用。請先移除既有設定。"))
                .font(.caption).foregroundStyle(.secondary)
        } else if let bridgeError {
            Text(bridgeError).font(.caption).foregroundStyle(.red)
        }
    }

    private func badge(_ text: String, network: Bool) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background((network ? Color.orange : Color.secondary).opacity(0.18), in: Capsule())
            .foregroundStyle(network ? .orange : .secondary)
    }

    private func featureToggle(_ feature: NetworkFeature) -> some View {
        Toggle(isOn: Binding(
            get: { binding(for: feature).wrappedValue },
            set: { newValue in
                if newValue { pending = feature }      // confirm before enabling
                else { binding(for: feature).wrappedValue = false; UsageStore.shared.refreshNow() }
            })) {
            HStack(spacing: 6) {
                Text(feature.title)
                badge(feature.usesNetwork ? lang.tr("needs internet", "需連網")
                                          : lang.tr("reads credentials", "讀本機憑證"),
                      network: feature.usesNetwork)
            }
        }
    }

    private func binding(for feature: NetworkFeature) -> Binding<Bool> {
        switch feature {
        case .codexQuota:   return $codexQuota
        case .showAccounts: return $showAccounts
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

    private func accountRow(_ name: String, provider: String, tool: AgentTool,
                            account: ServiceAccount?) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colors.color(for: tool)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(name).font(.system(size: 12.5, weight: .semibold))
                    Text(provider).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let a = account, !a.isEmpty {
                    Text([a.email, a.plan?.capitalized].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    Text(lang.tr("Not detected", "未偵測到"))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(account != nil ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(account != nil ? lang.tr("connected", "已連線") : lang.tr("offline", "未連線"))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
    }

    /// SMAppService.mainApp only works for a bundled, installed .app — not a bare
    /// `swift run` binary (which fails with "Invalid argument").
    private var isInstalledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
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
    @AppStorage(SettingsKeys.menuBarOrientation) private var orientation = "vertical"
    @AppStorage(SettingsKeys.menuBarShowIcon) private var showIcon = true

    private let claudeMetrics: [MenuBarMetric] =
        [.claudeTokens, .claudeFiveHour, .claudeWeekly, .claudeContext, .claudeMessages]
    private let codexMetrics: [MenuBarMetric] =
        [.codexTokens, .codexFiveHour, .codexWeekly, .codexContext, .codexMessages]

    var body: some View {
        Form {
            Section(lang.tr("Claude metrics", "Claude 指標")) {
                ForEach(claudeMetrics) { Toggle($0.settingsTitle, isOn: metricBinding($0)) }
            }
            Section(lang.tr("Codex metrics", "Codex 指標")) {
                ForEach(codexMetrics) { Toggle($0.settingsTitle, isOn: metricBinding($0)) }
            }
            Section(lang.tr("Combined", "合計")) {
                Toggle(MenuBarMetric.combinedTokens.settingsTitle,
                       isOn: metricBinding(.combinedTokens))
            }
            Section(lang.tr("Layout", "排列方式")) {
                Picker(lang.tr("Label & value", "標籤與數值"), selection: $orientation) {
                    Text(lang.tr("Stacked (label above)", "直向（上下）")).tag("vertical")
                    Text(lang.tr("Inline (side by side)", "橫向（並排）")).tag("horizontal")
                }
                Toggle(lang.tr("Show agent icon", "顯示 agent 圖示"), isOn: $showIcon)
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

// MARK: - Floating HUD

private struct FloatingSettings: View {
    @EnvironmentObject private var lang: LanguageStore
    @AppStorage(SettingsKeys.floatingEnabled) private var enabled = false
    @AppStorage(SettingsKeys.floatingShowClaude) private var showClaude = true
    @AppStorage(SettingsKeys.floatingShowCodex) private var showCodex = true
    @AppStorage(SettingsKeys.floatingIdleOpacity) private var idleOpacity = 0.7

    var body: some View {
        Form {
            Section {
                Toggle(lang.tr("Show floating desktop HUD", "顯示桌面浮動面板"), isOn: $enabled)
                    .onChange(of: enabled) { _, on in FloatingPanelController.shared.setEnabled(on) }
            }
            Section(lang.tr("HUD content", "面板內容")) {
                Toggle("Claude", isOn: $showClaude)
                Toggle("Codex", isOn: $showCodex)
                HStack {
                    Text(lang.tr("Idle opacity", "閒置透明度"))
                    Slider(value: $idleOpacity, in: 0.3...1.0)
                    Text("\(Int(idleOpacity * 100))%").font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }
}
