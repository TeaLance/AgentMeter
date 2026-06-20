import Foundation

/// A normalized model identifier, shared by pricing and by-model aggregation so
/// the two always bucket on the same key. Folds dated snapshots
/// (`claude-haiku-4-5-20251001` → `claude-haiku-4-5`), strips bracket suffixes
/// (`claude-opus-4-8[1m]` → `claude-opus-4-8`), and maps `<synthetic>` / empty
/// to `.unknown`.
public struct ModelKey: Hashable, Sendable {
    public enum Vendor: Sendable { case anthropic, openai, unknown }

    public let id: String
    public let vendor: Vendor

    public static let unknown = ModelKey(id: "unknown", vendor: .unknown)

    private init(id: String, vendor: Vendor) {
        self.id = id
        self.vendor = vendor
    }

    public init(raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip a trailing bracketed segment, e.g. "[1m]".
        if let open = s.lastIndex(of: "["), s.hasSuffix("]") {
            s = String(s[..<open])
        }
        // Strip a trailing "-YYYYMMDD" dated-snapshot suffix.
        if let dash = s.lastIndex(of: "-") {
            let tail = s[s.index(after: dash)...]
            if tail.count == 8, tail.allSatisfy(\.isNumber) {
                s = String(s[..<dash])
            }
        }
        s = s.trimmingCharacters(in: .whitespaces)

        guard !s.isEmpty, s != "<synthetic>" else { self = .unknown; return }
        self.id = s
        self.vendor = ModelKey.vendor(for: s)
    }

    public var displayName: String { id }

    private static func vendor(for id: String) -> Vendor {
        if id.hasPrefix("claude") { return .anthropic }
        if id.hasPrefix("gpt") || id.hasPrefix("codex") || id.hasPrefix("o1") || id.hasPrefix("o3") {
            return .openai
        }
        return .unknown
    }
}
