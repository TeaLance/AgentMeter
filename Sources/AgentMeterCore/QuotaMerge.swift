import Foundation

/// Keep-last-good logic for subscription quota windows. Pure functions, no I/O.
public enum QuotaMerge {
    /// A window whose reset time has passed is back to 0% with no known reset.
    public static func normalize(_ w: QuotaWindow, now: Date) -> QuotaWindow {
        if let r = w.resetsAt, r <= now { return QuotaWindow(usedPercent: 0, resetsAt: nil) }
        return w
    }

    /// Prefer the fresh value; fall back to the previous one; both nil -> nil.
    /// The result is always normalised against `now`.
    public static func merge(previous: QuotaWindow?, fresh: QuotaWindow?, now: Date) -> QuotaWindow? {
        if let fresh { return normalize(fresh, now: now) }
        if let previous { return normalize(previous, now: now) }
        return nil
    }
}
