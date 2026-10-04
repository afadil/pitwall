import Foundation

/// The last complete lines of a file, read without loading the whole file.
public struct FileTail: Sendable {
    /// Complete lines, oldest first. The partial first line of the window is dropped.
    public var lines: [Data]
    /// True when the window covers the file from byte 0.
    public var coversWholeFile: Bool
    public var fileSize: UInt64
    public var modified: Date?
    /// Bytes actually read from disk.
    public var bytesRead: Int
}

public enum TailReader {
    /// Reads at most `maxBytes` from the end of `url`. Opens the file read-only.
    public static func read(_ url: URL, maxBytes: Int) throws -> FileTail {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attributes[.modificationDate] as? Date

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let window = UInt64(max(0, maxBytes))
        let offset = size > window ? size - window : 0
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: Int(size - offset)) ?? Data()

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            // The window almost always starts mid-line. If it starts exactly on a
            // line boundary we lose one line, which is fine for a tail.
            lines.removeFirst()
        }
        return FileTail(
            lines: lines.map { Data($0) },
            coversWholeFile: offset == 0,
            fileSize: size,
            modified: modified,
            bytesRead: data.count
        )
    }

    /// Reads a growing window until `isEnough` is satisfied or `limit` is reached.
    public static func read(
        _ url: URL,
        initialBytes: Int,
        limit: Int,
        until isEnough: (FileTail) -> Bool
    ) throws -> FileTail {
        var budget = initialBytes
        while true {
            let tail = try read(url, maxBytes: budget)
            if isEnough(tail) || tail.coversWholeFile || budget >= limit {
                return tail
            }
            budget = min(limit, budget * 4)
        }
    }
}
