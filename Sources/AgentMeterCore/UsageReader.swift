import Foundation

/// Anything that can produce a `ToolUsage` snapshot for a given instant.
/// `now` is injected so callers (and tests) control the time windows.
public protocol UsageReader {
    func read(now: Date) throws -> ToolUsage
}
