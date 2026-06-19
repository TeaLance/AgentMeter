import Foundation

/// Urgency of a quota/usage meter, driven purely by how much *remains*.
/// This is deliberately separate from a service's identity colour: identity
/// answers "which tool?", status answers "how much is left?".
public enum StatusLevel: Sendable, Equatable {
    case normal   // plenty remains
    case warning  // getting tight
    case low      // nearly out
    case empty    // effectively exhausted

    /// Classify from a *used* percentage (0...100). Values are clamped.
    /// remaining = 100 - used:
    ///   remaining >= 50 normal · >= 25 warning · >= 10 low · else empty.
    public static func forUsed(percent used: Double) -> StatusLevel {
        let remaining = 100 - min(100, max(0, used))
        switch remaining {
        case 50...:    return .normal
        case 25..<50:  return .warning
        case 10..<25:  return .low
        default:       return .empty
        }
    }
}
