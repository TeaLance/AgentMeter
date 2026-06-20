import Foundation
import AgentMeterCore

/// Owns the latest usage snapshots and refreshes them on a timer.
/// Reading happens off the main actor; published values are updated on it.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var claude = ToolUsage(tool: .claudeCode, available: false)
    @Published private(set) var codex = ToolUsage(tool: .codex, available: false)
    @Published private(set) var claudeQuota = ClaudeQuota(available: false)
    // Networked Codex quota (only when the opt-in is enabled).
    @Published private(set) var codexFiveHour: QuotaWindow?
    @Published private(set) var codexWeekly: QuotaWindow?
    // Logged-in accounts (only when "show accounts" opt-in is enabled).
    @Published private(set) var claudeAccount: ServiceAccount?
    @Published private(set) var codexAccount: ServiceAccount?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var interval: TimeInterval

    init() {
        let stored = UserDefaults.standard.double(forKey: SettingsKeys.interval)
        self.interval = stored > 0 ? stored : 30
        refreshNow()
        startTimer()
    }

    /// Combined "billable" (cache-read-excluded) tokens used today.
    var combinedTodayBillable: Int {
        claude.today.billableTotal + codex.today.billableTotal
    }

    func setInterval(_ seconds: TimeInterval) {
        guard seconds > 0, seconds != interval else { return }
        interval = seconds
        startTimer()
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let now = Date()
            let claudeUsage = (try? ClaudeCodeReader().read(now: now))
                ?? ToolUsage(tool: .claudeCode, available: false, lastUpdated: now)
            let codexUsage = (try? CodexReader().read(now: now))
                ?? ToolUsage(tool: .codex, available: false, lastUpdated: now)
            let quota = ClaudeStatusReader().read()

            // Opt-in: read logged-in accounts from local credential files.
            let showAccounts = NetworkFeature.showAccounts.isEnabled
            let reader = CredentialReader()
            let claudeAcct = showAccounts ? reader.claude()?.account.nonEmpty : nil
            let codexAcct = showAccounts ? reader.codex()?.account.nonEmpty : nil

            // Opt-in: networked Codex 5h/weekly quota.
            var codex5h: QuotaWindow?
            var codexWk: QuotaWindow?
            if case let .ok(f, w) = await CodexQuotaClient().fetch() { codex5h = f; codexWk = w }

            await MainActor.run {
                self.claude = claudeUsage
                self.codex = codexUsage
                self.claudeQuota = quota
                self.codexFiveHour = codex5h
                self.codexWeekly = codexWk
                self.claudeAccount = claudeAcct
                self.codexAccount = codexAcct
                self.lastRefresh = now
                self.isRefreshing = false
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        t.tolerance = interval * 0.2
        timer = t
    }
}
