import Foundation
import SQLite3

/// Minimal but production-ready SQLite wrapper.
///
/// Why hand-rolled (no GRDB / SQLite.swift)?
/// - Zero external deps; ships with macOS.
/// - We only need a thin layer: open / exec / prepare / step / bind / column.
/// - Lets us own concurrency (actor) and lifecycle (deinit closes the DB).
///
/// Concurrency: SQLite is configured in **serialized** mode and the connection
/// is owned by an `actor`, so all calls are serialized at the language level
/// AND the C library level. No `@unchecked Sendable` hacks.
///
/// Memory: every prepared statement is finalized; transient strings use
/// `SQLITE_TRANSIENT` so SQLite copies the bytes — we don't keep a Swift
/// pointer alive past the call.
actor SQLite {
    enum DBError: Error, LocalizedError {
        case openFailed(String)
        case prepareFailed(String, sql: String)
        case stepFailed(String, sql: String)
        case execFailed(String, sql: String)
        case bindFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let msg):              return "SQLite open failed: \(msg)"
            case .prepareFailed(let msg, let sql):  return "SQLite prepare failed (\(msg)): \(sql)"
            case .stepFailed(let msg, let sql):     return "SQLite step failed (\(msg)): \(sql)"
            case .execFailed(let msg, let sql):     return "SQLite exec failed (\(msg)): \(sql)"
            case .bindFailed(let msg):              return "SQLite bind failed: \(msg)"
            }
        }
    }

    /// Bound parameter values. Keep this small — no `Date`/`UUID` here so the
    /// DAO layer is forced to make encoding decisions explicit (UTC-ms, RFC4122).
    enum Value: Sendable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
    }

    typealias Row = [String: Value]

    // MARK: – Lifecycle

    private var db: OpaquePointer?
    private let path: String

    /// Open (or create) a database file. Pragmas are tuned for a desktop mail
    /// cache: WAL + NORMAL sync gives durability without fsync-per-commit cost.
    init(path: String) throws {
        self.path = path

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close_v2(handle) }
            throw DBError.openFailed(msg)
        }
        self.db = handle

        // Tune for our workload — single-writer, many-reader cache.
        // We call sqlite3_exec directly here (rather than the isolated
        // `execNoSync`) because actor `init` is nonisolated and Swift 6
        // forbids calling isolated members from it.
        let pragmas = [
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = NORMAL",
            "PRAGMA temp_store = MEMORY",
            "PRAGMA foreign_keys = ON",
            "PRAGMA mmap_size = 134217728",   // 128 MiB
            "PRAGMA cache_size = -8000"       // ~8 MiB page cache
        ]
        for pragma in pragmas {
            var error: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(handle, pragma, nil, nil, &error)
            defer { if let error { sqlite3_free(error) } }
            guard rc == SQLITE_OK else {
                let msg = error.map { String(cString: $0) } ?? "unknown"
                sqlite3_close_v2(handle)
                throw DBError.execFailed(msg, sql: pragma)
            }
        }
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: – Exec / query

    /// Execute one or more statements without returning rows. Use for DDL
    /// and simple writes. For parameterized writes use `execute(_:params:)`.
    func exec(_ sql: String) throws {
        try execNoSync(sql)
    }

    /// Execute a parameterized statement. Returns affected-row count.
    @discardableResult
    func execute(_ sql: String, _ params: [Value] = []) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try prepare(sql: sql, into: &stmt)
        try bind(params, to: stmt)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DBError.stepFailed(lastErrorMessage(), sql: sql)
        }
        return Int(sqlite3_changes(db))
    }

    /// Run a query and decode rows lazily. The closure receives a row-cursor
    /// (one call per row); throwing aborts iteration and finalizes the stmt.
    func query(
        _ sql: String,
        _ params: [Value] = [],
        rowHandler: (Row) throws -> Void
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try prepare(sql: sql, into: &stmt)
        try bind(params, to: stmt)

        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw DBError.stepFailed(lastErrorMessage(), sql: sql)
            }
            try rowHandler(decode(stmt))
        }
    }

    /// Convenience: collect every row into an array. Avoid for very large
    /// result sets — prefer the streaming `query` form.
    func queryAll(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        var rows: [Row] = []
        try query(sql, params) { rows.append($0) }
        return rows
    }

    func lastInsertRowID() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    // MARK: – Transactions
    //
    // We don't expose a closure-based `transaction` helper because the actor
    // model forces every SQLite call to be `async`, but a sync closure can't
    // `await`. Callers that need multi-statement atomicity should use
    // `BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK` directly via `exec`.

    // MARK: – Internals

    private func prepare(sql: String, into stmt: inout OpaquePointer?) throws {
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw DBError.prepareFailed(lastErrorMessage(), sql: sql)
        }
    }

    private func bind(_ params: [Value], to stmt: OpaquePointer?) throws {
        guard let stmt else { return }
        // SQLITE_TRANSIENT tells SQLite to copy. We rely on this so transient
        // Swift strings/Data don't have to outlive the bind call.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for (offset, value) in params.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .null:
                rc = sqlite3_bind_null(stmt, index)
            case .integer(let i):
                rc = sqlite3_bind_int64(stmt, index, i)
            case .real(let d):
                rc = sqlite3_bind_double(stmt, index, d)
            case .text(let s):
                rc = sqlite3_bind_text(stmt, index, s, -1, transient)
            case .blob(let data):
                rc = data.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, index, buf.baseAddress, Int32(data.count), transient)
                }
            }
            guard rc == SQLITE_OK else {
                throw DBError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func decode(_ stmt: OpaquePointer?) -> Row {
        guard let stmt else { return [:] }
        let count = sqlite3_column_count(stmt)
        var row: Row = [:]
        row.reserveCapacity(Int(count))

        for i in 0..<count {
            let name = sqlite3_column_name(stmt, i).map { String(cString: $0) } ?? "col\(i)"
            let type = sqlite3_column_type(stmt, i)
            switch type {
            case SQLITE_NULL:
                row[name] = .null
            case SQLITE_INTEGER:
                row[name] = .integer(sqlite3_column_int64(stmt, i))
            case SQLITE_FLOAT:
                row[name] = .real(sqlite3_column_double(stmt, i))
            case SQLITE_TEXT:
                if let cstr = sqlite3_column_text(stmt, i) {
                    row[name] = .text(String(cString: cstr))
                } else {
                    row[name] = .null
                }
            case SQLITE_BLOB:
                let bytes = sqlite3_column_bytes(stmt, i)
                if bytes > 0, let pointer = sqlite3_column_blob(stmt, i) {
                    row[name] = .blob(Data(bytes: pointer, count: Int(bytes)))
                } else {
                    row[name] = .blob(Data())
                }
            default:
                row[name] = .null
            }
        }
        return row
    }

    private func execNoSync(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &error)
        defer { if let error { sqlite3_free(error) } }
        guard rc == SQLITE_OK else {
            let msg = error.map { String(cString: $0) } ?? "unknown"
            throw DBError.execFailed(msg, sql: sql)
        }
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "(no db)" }
        return String(cString: sqlite3_errmsg(db))
    }
}

// MARK: - Row helpers

extension SQLite.Row {
    func int(_ key: String) -> Int64? {
        if case .integer(let i) = self[key] { return i }
        return nil
    }
    func double(_ key: String) -> Double? {
        if case .real(let d) = self[key] { return d }
        if case .integer(let i) = self[key] { return Double(i) }
        return nil
    }
    func text(_ key: String) -> String? {
        if case .text(let s) = self[key] { return s }
        return nil
    }
    func blob(_ key: String) -> Data? {
        if case .blob(let d) = self[key] { return d }
        return nil
    }
    func bool(_ key: String) -> Bool? {
        int(key).map { $0 != 0 }
    }
}
