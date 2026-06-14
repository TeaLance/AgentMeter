import Foundation
import AgentMeterCore

/// Owns the latest usage snapshots and refreshes them on a timer.
/// Reading happens off the main actor; published values are updated on it.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var claude = ToolUsage(tool: .claudeCode, available: false)
    @Published private(set) var codex = ToolUsage(tool: .codex, available: false)
    @Published private(set) var claudeQuota = ClaudeQuota(available: false)
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
            await MainActor.run {
                self.claude = claudeUsage
                self.codex = codexUsage
                self.claudeQuota = quota
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
