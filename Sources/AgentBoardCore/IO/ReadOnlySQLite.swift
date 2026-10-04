import Foundation
import SQLite3

public struct SQLiteError: Error, Sendable, CustomStringConvertible {
    public var code: Int32
    public var message: String
    public var description: String { "\(message) (\(code))" }
}

/// A minimal read-only SQLite connection that never writes to, locks or creates
/// files next to another app's database.
///
/// - No `-wal` file, or an empty one: the database is opened with
///   `SQLITE_OPEN_READONLY` and `immutable=1`, so SQLite takes no locks and
///   never creates `-wal`/`-shm` files.
/// - A non-empty `-wal` (the app is writing): even a read-only connection would
///   map and update the `-shm` index. Instead the database and its WAL are copied
///   into a private temporary folder and the copy is read, then deleted.
public final class ReadOnlySQLite {
    private var db: OpaquePointer?
    private var scratch: URL?

    public init(path: String) throws {
        let fm = FileManager.default
        let walSize = ((try? fm.attributesOfItem(atPath: path + "-wal"))?[.size] as? NSNumber)?.intValue ?? 0

        var openPath = path
        var immutable = true
        if walSize > 0 {
            let folder = fm.temporaryDirectory.appending(path: "agentboard-sqlite-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            scratch = folder
            let copy = folder.appending(path: (path as NSString).lastPathComponent)
            try fm.copyItem(atPath: path, toPath: copy.path)
            try? fm.copyItem(atPath: path + "-wal", toPath: copy.path + "-wal")
            openPath = copy.path
            immutable = false
        }

        var components = URLComponents()
        components.scheme = "file"
        components.path = openPath
        // The private copy must be writable so SQLite can replay its WAL into it.
        components.queryItems = immutable
            ? [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
            : [URLQueryItem(name: "mode", value: "rw")]
        guard let uri = components.string else {
            throw SQLiteError(code: SQLITE_CANTOPEN, message: "Bad path")
        }

        let access = immutable ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        let flags = access | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(uri, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Can't open database"
            sqlite3_close(db)
            self.db = nil
            if let scratch { try? FileManager.default.removeItem(at: scratch) }
            throw SQLiteError(code: rc, message: message)
        }
        sqlite3_busy_timeout(db, 500)
        sqlite3_exec(db, "PRAGMA query_only = 1", nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    /// Column names of `table`, empty when the table doesn't exist.
    public func columns(of table: String) throws -> Set<String> {
        let rows = try query("PRAGMA table_info(\(Self.quoteIdentifier(table)))")
        return Set(rows.compactMap { $0["name"] as? String })
    }

    /// Runs one statement and returns every row as column → value
    /// (`String`, `Int64`, `Double`, or absent for NULL).
    public func query(_ sql: String) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String: Any]] = []
        let count = sqlite3_column_count(statement)
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError() }
            var row: [String: Any] = [:]
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, i))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, i) {
                        row[name] = String(decoding: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, i))), as: UTF8.self)
                    }
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }

    static func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
    }
}
