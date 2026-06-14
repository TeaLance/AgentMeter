import Foundation

/// Maximum context window (in tokens) for a given model id.
///
/// Claude models advertise a 1M-token window via a `[1m]` suffix on the id
/// (e.g. `claude-opus-4-8[1m]`); otherwise the standard window is 200k.
public func contextWindow(forModelID modelID: String?) -> Int {
    if let id = modelID, id.lowercased().contains("[1m]") {
        return 1_000_000
    }
    return 200_000
}
