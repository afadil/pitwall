import Foundation

/// Reads and writes `organization.json`. Writes are atomic (write a new file,
/// then swap it in), so a crash can't leave a half-written file.
public struct OrganizationStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Pitwall/organization.json`
    public static var standardURL: URL {
        applicationSupport.appending(path: "Pitwall", directoryHint: .isDirectory).appending(path: "organization.json")
    }

    /// Where builds from before the rename (Agent Board) kept the file.
    public static var legacyURL: URL {
        applicationSupport.appending(path: "Agent Board", directoryHint: .isDirectory).appending(path: "organization.json")
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    }

    /// Moves a file left by an older build into place, unless this store already has one.
    /// Returns true when a file was moved.
    @discardableResult
    public func adoptLegacyFile(at legacy: URL) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) else { return false }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: url)
            try? fm.removeItem(at: legacy.deletingLastPathComponent())  // only succeeds if now empty
            return true
        } catch {
            return false
        }
    }

    public struct Loaded: Sendable {
        public var organization: Organization
        /// True when no file existed yet (first launch).
        public var isNew: Bool
        /// Set when the file couldn't be read; it was moved aside, not deleted.
        public var problem: String?
    }

    public func load() -> Loaded {
        guard let data = try? Data(contentsOf: url) else {
            return Loaded(organization: Organization(), isNew: true, problem: nil)
        }
        do {
            let organization = try Self.decoder.decode(Organization.self, from: data)
            return Loaded(organization: organization, isNew: false, problem: nil)
        } catch {
            // Keep the unreadable file for the user instead of overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return Loaded(
                organization: Organization(), isNew: false,
                problem: "Can't read organization.json. It was kept as \(aside.lastPathComponent).")
        }
    }

    public func save(_ organization: Organization) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(organization).write(to: url, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
