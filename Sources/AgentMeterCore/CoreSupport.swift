import Foundation

/// Parse an ISO-8601 timestamp, tolerating presence/absence of fractional seconds.
/// Both Claude Code and Codex write UTC timestamps ending in `Z`.
func parseISOTimestamp(_ string: String) -> Date? {
    isoWithFractional.date(from: string) ?? isoPlain.date(from: string)
}

private let isoWithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// Recursively collect `*.jsonl` files under `directory`. Returns [] if it can't enumerate.
func jsonlFiles(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var result: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        result.append(url)
    }
    return result
}

/// Last-modified time of a file, or `.distantFuture` if unknown (so it is never skipped).
func modificationDate(of url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
}

/// True when `directory` exists and is a directory.
func directoryExists(_ directory: URL) -> Bool {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir)
    return exists && isDir.boolValue
}
