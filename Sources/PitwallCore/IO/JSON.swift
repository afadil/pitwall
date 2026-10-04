import Foundation

enum JSONLine {
    /// Parses one JSONL line into a dictionary; nil for anything else.
    static func object(_ line: Data) -> [String: Any]? {
        guard let first = line.first(where: { $0 != 0x20 && $0 != 0x09 }), first == UInt8(ascii: "{") else { return nil }
        return (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any]
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

/// Decodes a value or nil, so one malformed element doesn't sink the array.
struct Lenient<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
