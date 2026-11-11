import Foundation

/// The newest 5h / weekly quota snapshot found in Codex's local rollout files.
public struct CodexLocalQuota: Equatable, Sendable {
    public var fiveHour: QuotaWindow?
    public var weekly: QuotaWindow?
    /// Timestamp of the rollout line the values came from.
    public var timestamp: Date

    public init(fiveHour: QuotaWindow?, weekly: QuotaWindow?, timestamp: Date) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.timestamp = timestamp
    }
}

/// Reads `payload.rate_limits` from `~/.codex/sessions/**/rollout-*.jsonl` as an
/// offline fallback for the networked Codex quota. Never throws, never touches the network.
public struct CodexLocalQuotaReader {
    private let sessionsDirectory: URL
    private let maxFiles: Int
    private let tailBytes: Int

    public init(sessionsDirectory: URL, maxFiles: Int = 5, tailBytes: Int = 1_048_576) {
        self.sessionsDirectory = sessionsDirectory
        self.maxFiles = maxFiles
        self.tailBytes = tailBytes
    }

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(sessionsDirectory: home.appendingPathComponent(".codex/sessions", isDirectory: true))
    }

    public func read() -> CodexLocalQuota? {
        guard directoryExists(sessionsDirectory) else { return nil }
        let files = jsonlFiles(in: sessionsDirectory)
            .map { ($0, modificationDate(of: $0)) }
            .sorted { $0.1 > $1.1 }
            .prefix(maxFiles)
        for (file, _) in files {
            if let found = latest(in: file) { return found }
        }
        return nil
    }

    private func latest(in file: URL) -> CodexLocalQuota? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return nil }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // possibly truncated first line

        for raw in lines.reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw))) as? [String: Any],
                  let ts = (obj["timestamp"] as? String).flatMap(parseISOTimestamp),
                  let payload = obj["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }
            let primary = limits["primary"] as? [String: Any]
            let secondary = limits["secondary"] as? [String: Any]
            if primary == nil && secondary == nil { continue }

            var five: QuotaWindow?
            var week: QuotaWindow?
            for (raw, isPrimary) in [(primary, true), (secondary, false)] {
                guard let raw, let parsed = window(raw, lineTime: ts) else { continue }
                switch parsed.minutes ?? (isPrimary ? 300 : 10080) {
                case 300: five = parsed.window
                case 10080: week = parsed.window
                default: break
                }
            }
            if five == nil && week == nil { continue }
            return CodexLocalQuota(fiveHour: five, weekly: week, timestamp: ts)
        }
        return nil
    }

    private func window(_ d: [String: Any], lineTime: Date) -> (window: QuotaWindow, minutes: Int?)? {
        guard let used = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        var resets: Date?
        if let at = (d["resets_at"] as? NSNumber)?.doubleValue {
            resets = Date(timeIntervalSince1970: at > 1e11 ? at / 1000 : at)
        } else if let secs = (d["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resets = lineTime.addingTimeInterval(secs)   // relative to the line, not "now"
        }
        let minutes = (d["window_minutes"] as? NSNumber)?.intValue
        return (QuotaWindow(usedPercent: used, resetsAt: resets), minutes)
    }
}
