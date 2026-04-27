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

