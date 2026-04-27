import Foundation

/// Persistence for `MailAccount`. The DAO is a thin façade — no caching,
/// no observation. Callers (services) are expected to debounce writes.
struct AccountDAO {
    private let db: MailDatabase

    init(db: MailDatabase) { self.db = db }

    // MARK: – Read

    func all() async throws -> [MailAccount] {
        let rows = try await db.sqlite.queryAll(
            "SELECT * FROM accounts ORDER BY sort_index ASC, created_at ASC"
        )
        return rows.compactMap(Self.decode)
    }

    func find(id: UUID) async throws -> MailAccount? {
        let rows = try await db.sqlite.queryAll(
            "SELECT * FROM accounts WHERE id = ? LIMIT 1",
            [.text(id.uuidString)]
        )
        return rows.first.flatMap(Self.decode)
    }

    // MARK: – Write

    func upsert(_ account: MailAccount) async throws {
        let now = Self.nowMs()
        try await db.sqlite.execute(
            """
            INSERT INTO accounts (
                id, provider_type, display_name, email_address, status,
                last_synced_at, last_error, is_enabled, sort_index, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider_type   = excluded.provider_type,
                display_name    = excluded.display_name,
                email_address   = excluded.email_address,
                status          = excluded.status,
                last_synced_at  = excluded.last_synced_at,
                last_error      = excluded.last_error,
                is_enabled      = excluded.is_enabled,
                updated_at      = excluded.updated_at
            """,
            [
                .text(account.id.uuidString),
                .text(account.providerType.rawValue),
                .text(account.displayName),
                .text(account.emailAddress),
                .text(account.status.rawValue),
                account.lastSyncedAt.map { .integer(Int64($0.timeIntervalSince1970 * 1000)) } ?? .null,
                account.lastErrorMessage.map { .text($0) } ?? .null,
                .integer(account.isEnabled ? 1 : 0),
                .integer(now),
                .integer(now)
            ]
        )
    }

    func remove(id: UUID) async throws {
        try await db.sqlite.execute(
            "DELETE FROM accounts WHERE id = ?",
            [.text(id.uuidString)]
        )
        // FK CASCADE wipes folders/messages/attachments/sync_state for this account.
    }

    func updateSyncSuccess(id: UUID, at date: Date = Date()) async throws {
        try await db.sqlite.execute(
            "UPDATE accounts SET status = 'connected', last_synced_at = ?, last_error = NULL, updated_at = ? WHERE id = ?",
            [
                .integer(Int64(date.timeIntervalSince1970 * 1000)),
                .integer(Self.nowMs()),
                .text(id.uuidString)
            ]
        )
    }

    func updateSyncFailure(id: UUID, message: String) async throws {
        try await db.sqlite.execute(
            "UPDATE accounts SET status = 'error', last_error = ?, updated_at = ? WHERE id = ?",
            [.text(message), .integer(Self.nowMs()), .text(id.uuidString)]
        )
    }

    // MARK: – Decode

    static func decode(_ row: SQLite.Row) -> MailAccount? {
        guard
            let idStr = row.text("id"),
            let id = UUID(uuidString: idStr),
            let providerStr = row.text("provider_type"),
            let providerType = MailProviderType(rawValue: providerStr),
            let email = row.text("email_address"),
            let statusStr = row.text("status"),
            let status = MailAccountConnectionStatus(rawValue: statusStr)
        else { return nil }

        let lastSync = row.int("last_synced_at").map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }

        return MailAccount(
            id: id,
            providerType: providerType,
            displayName: row.text("display_name") ?? "",
            emailAddress: email,
            status: status,
            lastSyncedAt: lastSync,
            lastErrorMessage: row.text("last_error"),
            isEnabled: row.bool("is_enabled") ?? true
        )
    }

    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
