import Foundation

/// Bounds memory per record instead of dropping an entire long-running session.
enum JSONLStreamReader {
    struct Result {
        let trailingData: Data
        let discardingLine: Bool
        let bytesRead: Int
    }

    static let maxLineBytes = 8 * 1024 * 1024

    /// Foundation's JSON strings may share the much larger input allocation.
    /// Cache a detached small string rather than retaining a whole log record.
    static func detachedString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        return String(decoding: Array(text.utf8), as: UTF8.self)
    }

    static func read(
        _ url: URL,
        fromOffset offset: Int = 0,
        throughOffset end: Int,
        carryover: Data = Data(),
        discardingLine: Bool = false,
        requiredMarker: Data? = nil,
        onObject: ([String: Any]) -> Void
    ) -> Result? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return nil }
        var buffer = carryover
        var discarding = discardingLine
        var bytesRead = 0

        func decode(_ data: Data, terminated: Bool) -> Bool {
            // Most records (tool output, prompts) carry no usage. A byte search
            // is far cheaper than JSON-decoding them only to discard the result.
            // An unterminated tail may be cut before its marker, so it must be
            // parsed to learn whether it is complete.
            if terminated, let requiredMarker, data.range(of: requiredMarker) == nil { return true }
            // Drain Foundation's temporary objects per record, rather than
            // retaining a whole multi-GB scan until the dispatch block ends.
            return autoreleasepool {
                let repaired = Data(String(decoding: data, as: UTF8.self).utf8)
                guard let object = try? JSONSerialization.jsonObject(with: repaired) as? [String: Any] else {
                    return false
                }
                onObject(object)
                return true
            }
        }

        while bytesRead < end - offset {
            // FileHandle may return autoreleased NSData; draining only the JSON
            // decoder would still retain every read chunk for the full scan.
            let read: Data? = autoreleasepool {
                try? handle.read(upToCount: min(64 * 1024, end - offset - bytesRead))
            }
            guard let chunk = read,
                  !chunk.isEmpty else { return nil }
            bytesRead += chunk.count
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 0x0A)
                let stop = newline ?? chunk.endIndex
                if !discarding {
                    if buffer.count + chunk.distance(from: start, to: stop) > maxLineBytes {
                        buffer.removeAll(keepingCapacity: false)
                        discarding = true
                    } else {
                        buffer.append(contentsOf: chunk[start..<stop])
                    }
                }
                if let newline {
                    if !discarding && !buffer.isEmpty { _ = decode(buffer, terminated: true) }
                    buffer.removeAll(keepingCapacity: true)
                    discarding = false
                    start = chunk.index(after: newline)
                } else {
                    break
                }
            }
        }
        // A complete final record is valid without a trailing newline. Keep an
        // incomplete record (or its discard state) for the next append.
        if !discarding && !buffer.isEmpty && decode(buffer, terminated: false) {
            buffer.removeAll(keepingCapacity: false)
        }
        // Empty carryover must not retain the largest record's allocation in
        // every file cache (hundreds of files can otherwise retain gigabytes).
        if buffer.isEmpty { buffer = Data() }
        return Result(trailingData: buffer, discardingLine: discarding, bytesRead: bytesRead)
    }
}
