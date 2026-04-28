import Foundation

/// Owns the single SQLite connection used by the app.
///
/// Lifecycle:
/// 1. App launch builds `MailDatabase.live` once via `AppContainer`.
/// 2. The handle lives as long as the process; macOS will flush WAL on quit.
/// 3. DAOs are stateless thin façades over the same actor — they can be
///    created and dropped freely without touching the connection.
///
/// On-disk path: `~/Library/Application Support/MailStream/mailstream.sqlite`
/// (Application Support — survives cache eviction, backed up by Time Machine
/// unless the user explicitly excludes it.)
actor MailDatabase {

    static let currentVersion: Int = 1

    let sqlite: SQLite
    /// On-disk path that this connection was opened against. Exposed so
    /// debug UI can show "where does my data live?" without re-deriving
    /// the path through `defaultURL()` (which can disagree with the
    /// in-memory fallback path used when AppContainer can't reach
    /// Application Support).
    nonisolated let fileURL: URL

    static func defaultURL() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MailStream", isDirectory: true)

        if fm.fileExists(atPath: support.path) == false {
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
        }
        return support.appendingPathComponent("mailstream.sqlite", isDirectory: false)
    }

    /// Open (or create) the database at `url`. Migrations run lazily — call
    /// `prepare()` before the first DAO use. We split init this way so the
    /// composition root (AppContainer) can stay synchronous while the
    /// async migration step runs from `AppState.bootstrap()`.
    init(url: URL) throws {
        self.fileURL = url
        self.sqlite = try SQLite(path: url.path)
    }

    /// Run any pending schema migrations. Idempotent.
    func prepare() async throws {
        try await migrate()
    }

    // MARK: - Migrations

    private func migrate() async throws {
        // Bootstrap version table the very first time.
        try await sqlite.exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);")
        let current = try await currentSchemaVersion()

        if current < 1 {
            try await applyV1()
            try await setSchemaVersion(1)
        }
        // Future migrations chain here:
        //   if current < 2 { try await applyV2(); try await setSchemaVersion(2) }
    }

    private func applyV1() async throws {
        // We can't pass an async closure to SQLite.transaction (sync block),
        // so we inline BEGIN/COMMIT manually. SQLite is itself an actor so
        // the calls are still serialized.
        try await sqlite.exec("BEGIN IMMEDIATE")
        do {
            for sql in V1Schema.statements {
                try await sqlite.exec(sql)
            }
            try await sqlite.exec("COMMIT")
        } catch {
            _ = try? await sqlite.exec("ROLLBACK")
            throw error
        }
    }

    private func currentSchemaVersion() async throws -> Int {
        let rows = try await sqlite.queryAll("SELECT MAX(version) AS v FROM schema_version")
        return Int(rows.first?.int("v") ?? 0)
    }

    private func setSchemaVersion(_ version: Int) async throws {
        try await sqlite.execute(
            "INSERT OR REPLACE INTO schema_version(version) VALUES(?)",
            [.integer(Int64(version))]
        )
    }

    // MARK: - Maintenance

    /// Compact the database. Fast on WAL — does a checkpoint plus VACUUM.
    /// Safe to call from a background `Task` on app idle.
    func compact() async throws {
        try await sqlite.exec("PRAGMA wal_checkpoint(TRUNCATE);")
        try await sqlite.exec("VACUUM;")
    }

    /// **Destructive.** Drop every user-owned object in this database
    /// (tables, views, triggers, indexes — anything not prefixed
    /// `sqlite_`) and re-run schema migrations from scratch. Used by
    /// the debug "Reset local cache" affordance in Settings while we
    /// don't yet trust the persistence path end-to-end.
    ///
    /// We intentionally drop and re-create rather than `DELETE FROM`
    /// every table — schema drift bugs are exactly what this surfaces,
    /// and a fresh `CREATE TABLE` round-trip is the cheapest way to
    /// confirm the migration code still produces a usable shape.
    ///
    /// FK off → drop → FK on so dropping in any order works regardless
    /// of cascade direction. Caller is responsible for invalidating any
    /// in-memory caches (body store, header snapshots, …) that mirror
    /// rows we just nuked.
    func wipeAndReset() async throws {
        try await sqlite.exec("PRAGMA foreign_keys = OFF")
        defer { Task { try? await sqlite.exec("PRAGMA foreign_keys = ON") } }

        // Collect every object name we own. `sqlite_master` reflects the
        // live schema; filtering out `sqlite_%` keeps SQLite's own
        // internals (sqlite_sequence, sqlite_stat*) untouched.
        let rows = try await sqlite.queryAll(
            "SELECT name, type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
        )

        // Drop in this order: triggers → views → indexes → tables.
        // Auto-indexes / -triggers attached to a table will go away with
        // the table itself, so explicit drops are belt-and-suspenders.
        let groups: [(String, String)] = [
            ("trigger", "DROP TRIGGER IF EXISTS"),
            ("view",    "DROP VIEW IF EXISTS"),
            ("index",   "DROP INDEX IF EXISTS"),
            ("table",   "DROP TABLE IF EXISTS")
        ]
        for (kind, prefix) in groups {
            for row in rows where row.text("type") == kind {
                guard let name = row.text("name") else { continue }
                // Quoting handles names that collide with reserved words.
                try await sqlite.exec("\(prefix) \"\(name)\"")
            }
        }

        // Re-apply migrations. After the drop above the schema_version
        // table is gone, so `migrate()` re-creates it and runs V1 from
        // scratch.
        try await migrate()
    }

    /// On-disk byte size of the SQLite file plus its WAL / SHM
    /// sidecars. Returns 0 if the file isn't reachable (unwritable
    /// volume, missing path, …) — this is debug-surface telemetry, not
    /// a hard contract.
    nonisolated func fileSizeBytes() -> Int64 {
        let fm = FileManager.default
        let suffixes = ["", "-wal", "-shm"]
        var total: Int64 = 0
        for suffix in suffixes {
            let path = fileURL.path + suffix
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            } else if let attrs = try? fm.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int {
                total += Int64(size)
            }
        }
        return total
    }

    /// Best-effort wipe of cached message bodies older than `cutoff`.
    /// Headers are kept; only bulky body_text/body_html columns are nulled.
    /// This is the primary memory/disk control valve.
    func evictBodies(olderThan cutoff: Date) async throws {
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
        try await sqlite.execute(
            """
            UPDATE messages
               SET body_text = NULL,
                   body_html = NULL,
                   body_loaded = 0,
                   updated_at = ?
             WHERE body_loaded = 1
               AND received_at < ?
            """,
            [.integer(Int64(Date().timeIntervalSince1970 * 1000)), .integer(cutoffMs)]
        )
    }
}

