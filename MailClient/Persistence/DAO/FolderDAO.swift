import Foundation

/// Folder taxonomy. Providers map their native folders into one of these
/// roles so the rest of the app can speak in logical terms.
enum MailFolderRole: String, Codable, Sendable, CaseIterable {
    case inbox, sent, drafts, trash, junk, archive, starred, important, other
}

struct MailFolder: Identifiable, Hashable, Sendable {
    let id: Int64                      // SQLite rowid
    let accountID: UUID
    let remoteID: String               // IMAP raw / Graph id
    let name: String                   // decoded display name
    let role: MailFolderRole
    var unreadCount: Int
    var totalCount: Int
}

struct FolderDAO {
    private let db: MailDatabase
    init(db: MailDatabase) { self.db = db }

    func all(accountID: UUID) async throws -> [MailFolder] {
        let rows = try await db.sqlite.queryAll(
            "SELECT * FROM folders WHERE account_id = ? ORDER BY role, name",
            [.text(accountID.uuidString)]
        )
        return rows.compactMap(Self.decode)
    }

    func find(accountID: UUID, role: MailFolderRole) async throws -> MailFolder? {
        let rows = try await db.sqlite.queryAll(
            "SELECT * FROM folders WHERE account_id = ? AND role = ? LIMIT 1",
            [.text(accountID.uuidString), .text(role.rawValue)]
        )
        return rows.first.flatMap(Self.decode)
    }

    /// Upsert by (account, remote_id). Returns row id.
    @discardableResult
    func upsert(
        accountID: UUID,
        remoteID: String,
        name: String,
        role: MailFolderRole,
        attributes: [String] = []
    ) async throws -> Int64 {
        let attrs = (try? String(data: JSONEncoder().encode(attributes), encoding: .utf8)) ?? "[]"
        try await db.sqlite.execute(
            """
            INSERT INTO folders (account_id, remote_id, name, role, attributes)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(account_id, remote_id) DO UPDATE SET
                name = excluded.name,
                role = excluded.role,
                attributes = excluded.attributes
            """,
            [
                .text(accountID.uuidString),
                .text(remoteID),
                .text(name),
                .text(role.rawValue),
                .text(attrs)
            ]
        )
        let rows = try await db.sqlite.queryAll(
            "SELECT id FROM folders WHERE account_id = ? AND remote_id = ?",
            [.text(accountID.uuidString), .text(remoteID)]
        )
        return rows.first?.int("id") ?? 0
    }

    func updateCounts(folderID: Int64, unread: Int, total: Int) async throws {
        try await db.sqlite.execute(
            "UPDATE folders SET unread_count = ?, total_count = ? WHERE id = ?",
            [.integer(Int64(unread)), .integer(Int64(total)), .integer(folderID)]
        )
    }

    static func decode(_ row: SQLite.Row) -> MailFolder? {
        guard
            let id = row.int("id"),
            let accountIDStr = row.text("account_id"),
            let accountID = UUID(uuidString: accountIDStr),
            let remoteID = row.text("remote_id"),
            let name = row.text("name"),
            let roleStr = row.text("role"),
            let role = MailFolderRole(rawValue: roleStr)
        else { return nil }

        return MailFolder(
            id: id,
            accountID: accountID,
            remoteID: remoteID,
            name: name,
            role: role,
            unreadCount: Int(row.int("unread_count") ?? 0),
            totalCount: Int(row.int("total_count") ?? 0)
        )
    }
}

// MARK: - Sync state

struct SyncCursor: Sendable {
    var lastUID: Int64
    var uidValidity: Int64?
    var highestModseq: Int64?
    var lastFullSync: Date?
}

struct SyncStateDAO {
    private let db: MailDatabase
    init(db: MailDatabase) { self.db = db }

    func cursor(folderID: Int64) async throws -> SyncCursor {
        let rows = try await db.sqlite.queryAll(
            "SELECT * FROM sync_state WHERE folder_id = ? LIMIT 1",
            [.integer(folderID)]
        )
        guard let row = rows.first else {
            return SyncCursor(lastUID: 0, uidValidity: nil, highestModseq: nil, lastFullSync: nil)
        }
        return SyncCursor(
            lastUID: row.int("last_uid") ?? 0,
            uidValidity: row.int("uidvalidity"),
            highestModseq: row.int("highest_modseq"),
            lastFullSync: row.int("last_full_sync").map {
                Date(timeIntervalSince1970: TimeInterval($0) / 1000)
            }
        )
    }

    func record(folderID: Int64, cursor: SyncCursor) async throws {
        try await db.sqlite.execute(
            """
            INSERT INTO sync_state (folder_id, last_uid, uidvalidity, highest_modseq, last_full_sync)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(folder_id) DO UPDATE SET
                last_uid = excluded.last_uid,
                uidvalidity = excluded.uidvalidity,
                highest_modseq = excluded.highest_modseq,
                last_full_sync = excluded.last_full_sync
            """,
            [
                .integer(folderID),
                .integer(cursor.lastUID),
                cursor.uidValidity.map { .integer($0) } ?? .null,
                cursor.highestModseq.map { .integer($0) } ?? .null,
                cursor.lastFullSync.map { .integer(Int64($0.timeIntervalSince1970 * 1000)) } ?? .null
            ]
        )
    }
}
