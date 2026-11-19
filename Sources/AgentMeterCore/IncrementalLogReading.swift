import Foundation

/// Byte-level helpers and an incremental per-file row cache for JSONL logs.
///
/// Logs are append-only, so each refresh only needs the bytes added since the
/// previous one. Lines are split on 0x0A directly on the bytes (a UTF-8
/// continuation byte can never be 0x0A) and only lines that contain a marker
/// byte sequence are ever decoded.

/// Invoke `body` for every non-empty line in `data`. The Bool is `true` when the
/// line is terminated by `\n`, `false` for an unterminated trailing segment.
/// Returns the number of bytes consumed through the last `\n` (inclusive).
@discardableResult
func scanLines(_ data: Data, _ body: (UnsafeRawBufferPointer, Bool) -> Void) -> Int {
    data.withUnsafeBytes { raw -> Int in
        guard let base = raw.baseAddress else { return 0 }
        let count = raw.count
        var start = 0
        var consumed = 0
        while start < count {
            if let hit = memchr(base + start, 0x0A, count - start) {
                let end = base.distance(to: UnsafeRawPointer(hit))
                if end > start {
                    body(UnsafeRawBufferPointer(start: base + start, count: end - start), true)
                }
                start = end + 1
                consumed = start
            } else {
                body(UnsafeRawBufferPointer(start: base + start, count: count - start), false)
                break
            }
        }
        return consumed
    }
}

/// True when `line` contains the UTF-8 bytes of `needle`.
@inline(__always)
func lineContains(_ line: UnsafeRawBufferPointer, _ needle: StaticString) -> Bool {
    guard let base = line.baseAddress else { return false }
    return memmem(base, line.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
}

/// Stream every non-empty line of `file` (including an unterminated last line).
func forEachLine(in file: URL, _ body: (UnsafeRawBufferPointer) -> Void) {
    guard let data = try? Data(contentsOf: file) else { return }
    scanLines(data) { line, _ in body(line) }
}

/// I/O counters of an `IncrementalRowCache`. Every fallback in the cache still
/// yields correct numbers, so a broken fast path would only show up as extra
/// I/O; tests assert on these to catch that silent regression.
struct IncrementalReadStats: Equatable {
    /// Files opened for reading (the unchanged-file hot path must not open).
    var opens = 0
    /// Files digested from byte 0 (new, replaced, or failed append checks).
    var fullDigests = 0
    /// Bytes handed to the line scanner.
    var bytesDigested = 0
}

/// Thread-safe cache of compact rows extracted from append-only JSONL files,
/// keyed by file path. Survives across refreshes.
final class IncrementalRowCache<Row>: @unchecked Sendable {
    /// How many leading bytes are remembered to detect in-place rewrites.
    private static var headLength: Int { 64 }

    private struct Entry {
        var fileID: UInt64
        var modified: Date
        /// Bytes digested so far: always just past a `\n`.
        var offset: Int
        /// Up to `headLength` bytes from the start of the file when first digested.
        var head: [UInt8]
        var rows: [Row]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var stats = IncrementalReadStats()

    /// Rows for `file` in line order. `parse` maps one line to a row (or nil to skip).
    /// Rows from an unterminated trailing segment are returned but never cached.
    func rows(for file: URL, parse: (UnsafeRawBufferPointer) -> Row?) -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let path = file.path

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.intValue else {
            entries[path] = nil
            return []
        }
        let fileID = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date) ?? .distantPast

        // A cached entry is only a valid base when it is the same file and it has
        // not shrunk or been rewritten in place at the same size.
        var base: Entry? = entries[path]
        if let cached = base,
           cached.fileID != fileID
            || size < cached.offset
            || (size == cached.offset && cached.modified != modified) {
            base = nil
        }
        // Hot path: nothing new, no file I/O.
        if let b = base, size == b.offset { return b.rows }

        // Never leave a stale entry behind, whatever happens below.
        entries[path] = nil
        if size == 0 { return [] }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        stats.opens += 1

        var entry = Entry(fileID: fileID, modified: modified, offset: 0, head: [], rows: [])
        var chunk: Data?

        if let b = base, b.offset > 0 {
            // Appending: verify the digested part still looks like what we digested,
            // i.e. same leading bytes, and the digest ended right after a newline.
            if (try? handle.seek(toOffset: 0)) != nil,
               let h = try? handle.read(upToCount: b.head.count), Array(h) == b.head,
               (try? handle.seek(toOffset: UInt64(b.offset - 1))) != nil,
               let rest = try? handle.readToEnd(), rest.first == 0x0A {
                entry = b
                entry.modified = modified
                chunk = Data(rest.dropFirst())
            }
        }
        if chunk == nil {
            // New, replaced, or rewritten file: digest from the start.
            guard (try? handle.seek(toOffset: 0)) != nil, let all = try? handle.readToEnd() else { return [] }
            entry.head = Array(all.prefix(Self.headLength))
            chunk = all
            stats.fullDigests += 1
        }
        stats.bytesDigested += chunk!.count

        var fresh: [Row] = []
        var tail: [Row] = []
        let consumed = scanLines(chunk!) { line, complete in
            if let row = parse(line) {
                if complete { fresh.append(row) } else { tail.append(row) }
            }
        }
        entry.rows.append(contentsOf: fresh)
        entry.offset += consumed
        entries[path] = entry
        return tail.isEmpty ? entry.rows : entry.rows + tail
    }

    /// Drop entries for files that are no longer candidates.
    func retain(only paths: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        for key in entries.keys where !paths.contains(key) { entries[key] = nil }
    }

    var cachedPaths: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(entries.keys)
    }

    var ioStats: IncrementalReadStats {
        lock.lock(); defer { lock.unlock() }
        return stats
    }
}
