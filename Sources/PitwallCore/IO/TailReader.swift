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

enum JSONLine {
    /// Parses one JSONL line into a dictionary; nil for anything else.
    static func object(_ line: Data) -> [String: Any]? {
        guard let first = line.first(where: { $0 != 0x20 && $0 != 0x09 }), first == UInt8(ascii: "{") else { return nil }
        return (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any]
    }
}

enum Timestamp {
    /// Parses ISO 8601 timestamps as written by both apps
    /// (`2026-10-04T19:21:37.039Z`), with a slow-path fallback for offsets.
    static func parse(_ value: Any?) -> Date? {
        switch value {
        case let string as String:
            return parse(string)
        case let number as NSNumber:
            return fromEpoch(number.doubleValue)
        default:
            return nil
        }
    }

    static func parse(_ string: String) -> Date? {
        if let fast = fastParse(string) { return fast }
        if let date = try? Date(string, strategy: .iso8601) { return date }
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? withFraction.parse(string)
    }

    /// Epoch seconds or milliseconds, whichever the magnitude suggests.
    static func fromEpoch(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        // Anything above 10^11 is milliseconds (10^11 s is the year 5138).
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func fastParse(_ string: String) -> Date? {
        let utf8 = Array(string.utf8)
        guard utf8.count >= 20, utf8[4] == 0x2D, utf8[7] == 0x2D, utf8[10] == 0x54,
              utf8[13] == 0x3A, utf8[16] == 0x3A, utf8.last == 0x5A else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for i in range {
                let c = utf8[i]
                guard c >= 0x30, c <= 0x39 else { return nil }
                value = value * 10 + Int(c - 0x30)
            }
            return value
        }

        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        var fraction = 0.0
        if utf8[19] == 0x2E {
            var scale = 0.1
            for i in 20..<(utf8.count - 1) {
                let c = utf8[i]
                guard c >= 0x30, c <= 0x39 else { return nil }
                fraction += Double(c - 0x30) * scale
                scale /= 10
            }
        } else if utf8.count != 20 {
            return nil
        }

        // Days from civil (Howard Hinnant), avoids Calendar on the hot path.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second) + fraction
        return Date(timeIntervalSince1970: seconds)
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        guard let value = self[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func bool(_ key: String) -> Bool? {
        switch self[key] {
        case let b as Bool: b
        case let n as NSNumber: n.boolValue
        case let s as String: ["true", "1"].contains(s.lowercased())
        default: nil
        }
    }

    func date(_ key: String) -> Date? {
        Timestamp.parse(self[key])
    }

    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }
}
