import Foundation

/// Header-only summary used by list views. Body is **not** included.
/// Loaded eagerly from `messages` columns; FTS rows are not touched.
struct MailMessageSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let accountID: UUID
    let folderID: Int64
    /// Logical role of the parent folder. Populated by the JOIN in
    /// `summariesForAccount` so the read path can map a row back to
    /// the user-facing `SidebarItem` (inbox / sent / drafts / trash)
    /// without a second SELECT per message.
    let folderRole: MailFolderRole
    let remoteUID: Int64
    let subject: String
    let fromName: String
    let fromAddress: String
    let preview: String
    let receivedAt: Date
    let isUnread: Bool
    let isFlagged: Bool
    let hasAttachment: Bool
    let labelKeys: [String]
}

/// Raw body row from the DAO — text + optional HTML. The domain-level
/// `MailMessageBody` (paragraphs / highlights / closing) lives in the
/// model layer; repositories translate between the two.
struct MessageBodyRow: Sendable {
    let messageID: UUID
    let text: String?
    let html: String?
}

struct MessageDAO {
    private let db: MailDatabase
    init(db: MailDatabase) { self.db = db }

    // MARK: – Read

    /// Stream summaries (no body) for a folder, newest first, capped by `limit`.
    /// Use the streaming variant `enumerate` if you might display 10 000+ items
    /// — but the LazyVStack only renders visible rows so an `Array` of even
    /// 5 000 summaries is comfortably under 5 MB.
    /// Per-folder summaries. Joined to `folders` so callers get the
    /// role without a second round-trip — the list view needs it for
    /// SidebarItem mapping.
    func summaries(folderID: Int64, limit: Int = 200) async throws -> [MailMessageSummary] {
        let rows = try await db.sqlite.queryAll(
            """
            SELECT m.id, m.account_id, m.folder_id, m.remote_uid, m.subject,
                   m.from_name, m.from_address, m.preview, m.received_at,
                   m.flags_seen, m.flags_flagged, m.has_attachment, m.label_keys,
                   f.role AS folder_role
              FROM messages m
              LEFT JOIN folders f ON f.id = m.folder_id
             WHERE m.folder_id = ?
             ORDER BY m.received_at DESC
             LIMIT ?
            """,
            [.integer(folderID), .integer(Int64(limit))]
        )
        return rows.compactMap(Self.decodeSummary)
    }

    func summariesForAccount(_ accountID: UUID, limit: Int = 200) async throws -> [MailMessageSummary] {
        let rows = try await db.sqlite.queryAll(
            """
            SELECT m.id, m.account_id, m.folder_id, m.remote_uid, m.subject,
                   m.from_name, m.from_address, m.preview, m.received_at,
                   m.flags_seen, m.flags_flagged, m.has_attachment, m.label_keys,
                   f.role AS folder_role
              FROM messages m
              LEFT JOIN folders f ON f.id = m.folder_id
             WHERE m.account_id = ?
             ORDER BY m.received_at DESC
             LIMIT ?
            """,
            [.text(accountID.uuidString), .integer(Int64(limit))]
        )
        return rows.compactMap(Self.decodeSummary)
    }

    /// Lazy body load for the detail pane. Returns `nil` if the body has not
    /// been fetched yet (caller should ask the provider to fetch).
    func body(messageID: UUID) async throws -> MessageBodyRow? {
        let rows = try await db.sqlite.queryAll(
            "SELECT body_text, body_html, body_loaded FROM messages WHERE id = ? LIMIT 1",
            [.text(messageID.uuidString)]
        )
        guard let row = rows.first, (row.bool("body_loaded") ?? false) else { return nil }
        return MessageBodyRow(
            messageID: messageID,
            text: row.text("body_text"),
            html: row.text("body_html")
        )
    }

    /// Full-text search across subject / sender / preview / body. Returns
    /// summaries in BM25 rank order. Caller decides limit.
    func search(_ query: String, accountID: UUID? = nil, limit: Int = 100) async throws -> [MailMessageSummary] {
        // Sanitize: FTS5 has its own grammar; we wrap each token in quotes.
        let sanitized = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
            .joined(separator: " ")
        guard sanitized.isEmpty == false else { return [] }

        var sql = """
        SELECT m.id, m.account_id, m.folder_id, m.remote_uid, m.subject,
               m.from_name, m.from_address, m.preview, m.received_at,
               m.flags_seen, m.flags_flagged, m.has_attachment, m.label_keys
          FROM messages_fts f
          JOIN messages m ON m.rowid = f.rowid
         WHERE messages_fts MATCH ?
        """
        var params: [SQLite.Value] = [.text(sanitized)]
        if let accountID {
            sql += " AND m.account_id = ?"
            params.append(.text(accountID.uuidString))
        }
        sql += " ORDER BY bm25(messages_fts) ASC LIMIT ?"
        params.append(.integer(Int64(limit)))

        let rows = try await db.sqlite.queryAll(sql, params)
        return rows.compactMap(Self.decodeSummary)
    }

    // MARK: – Write

    /// Bulk insert/update headers. Wrap the call in a transaction for ~100x
    /// throughput on big batches:
    ///
    ///     try await sqlite.exec("BEGIN IMMEDIATE")
    ///     for header in headers { try await dao.upsertHeader(...) }
    ///     try await sqlite.exec("COMMIT")
    func upsertHeader(_ header: HeaderUpsert) async throws {
        let now = Self.nowMs()
        try await db.sqlite.execute(
            """
            INSERT INTO messages (
                id, account_id, folder_id, remote_uid, message_id, thread_id, in_reply_to,
                subject, from_name, from_address, to_addresses, cc_addresses, bcc_addresses,
                reply_to, preview, sent_at, received_at, size_bytes,
                flags_seen, flags_flagged, flags_answered, flags_draft,
                has_attachment, label_keys, body_loaded, body_text, body_html, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?,
                      ?, ?, ?, ?,
                      ?, ?, 0, NULL, NULL, ?)
            ON CONFLICT(account_id, folder_id, remote_uid) DO UPDATE SET
                subject         = excluded.subject,
                from_name       = excluded.from_name,
                from_address    = excluded.from_address,
                preview         = excluded.preview,
                flags_seen      = excluded.flags_seen,
                flags_flagged   = excluded.flags_flagged,
                flags_answered  = excluded.flags_answered,
                has_attachment  = excluded.has_attachment,
                label_keys      = excluded.label_keys,
                updated_at      = excluded.updated_at
            """,
            [
                .text(header.id.uuidString),
                .text(header.accountID.uuidString),
                .integer(header.folderID),
                .integer(header.remoteUID),
                header.messageID.map { .text($0) } ?? .null,
                header.threadID.map { .text($0) } ?? .null,
                header.inReplyTo.map { .text($0) } ?? .null,
                .text(header.subject),
                .text(header.fromName),
                .text(header.fromAddress),
                .text(Self.encodeJSON(header.toAddresses)),
                .text(Self.encodeJSON(header.ccAddresses)),
                .text(Self.encodeJSON(header.bccAddresses)),
                header.replyTo.map { .text($0) } ?? .null,
                .text(header.preview),
                .integer(Int64(header.sentAt.timeIntervalSince1970 * 1000)),
                .integer(Int64(header.receivedAt.timeIntervalSince1970 * 1000)),
                header.sizeBytes.map { .integer($0) } ?? .null,
                .integer(header.flagsSeen ? 1 : 0),
                .integer(header.flagsFlagged ? 1 : 0),
                .integer(header.flagsAnswered ? 1 : 0),
                .integer(header.flagsDraft ? 1 : 0),
                .integer(header.hasAttachment ? 1 : 0),
                .text(Self.encodeJSON(header.labelKeys)),
                .integer(now)
            ]
        )
    }

    func storeBody(messageID: UUID, text: String?, html: String?) async throws {
        try await db.sqlite.execute(
            """
            UPDATE messages
               SET body_text = ?, body_html = ?, body_loaded = 1, updated_at = ?
             WHERE id = ?
            """,
            [
                text.map { .text($0) } ?? .null,
                html.map { .text($0) } ?? .null,
                .integer(Self.nowMs()),
                .text(messageID.uuidString)
            ]
        )
    }

    func updateFlags(messageID: UUID, seen: Bool? = nil, flagged: Bool? = nil) async throws {
        var sets: [String] = []
        var params: [SQLite.Value] = []
        if let seen    { sets.append("flags_seen = ?");    params.append(.integer(seen ? 1 : 0)) }
        if let flagged { sets.append("flags_flagged = ?"); params.append(.integer(flagged ? 1 : 0)) }
        guard sets.isEmpty == false else { return }
        sets.append("updated_at = ?"); params.append(.integer(Self.nowMs()))
        params.append(.text(messageID.uuidString))
        try await db.sqlite.execute(
            "UPDATE messages SET \(sets.joined(separator: ", ")) WHERE id = ?",
            params
        )
    }

    func remove(messageID: UUID) async throws {
        try await db.sqlite.execute(
            "DELETE FROM messages WHERE id = ?",
            [.text(messageID.uuidString)]
        )
    }

    // MARK: – Decode

    static func decodeSummary(_ row: SQLite.Row) -> MailMessageSummary? {
        guard
            let idStr = row.text("id"), let id = UUID(uuidString: idStr),
            let accountStr = row.text("account_id"), let accountID = UUID(uuidString: accountStr),
            let folderID = row.int("folder_id"),
            let remoteUID = row.int("remote_uid"),
            let receivedMs = row.int("received_at")
        else { return nil }

        // Role comes from the JOIN — when the row is read through
        // `body(messageID:)` (no JOIN) the column is absent and we
        // fall back to `.other`. Callers that care about role go
        // through `summaries*`, which always projects it.
        let role = row.text("folder_role")
            .flatMap(MailFolderRole.init(rawValue:)) ?? .other

        let labels: [String] = row.text("label_keys")
            .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []

        return MailMessageSummary(
            id: id,
            accountID: accountID,
            folderID: folderID,
            folderRole: role,
            remoteUID: remoteUID,
            subject: row.text("subject") ?? "",
            fromName: row.text("from_name") ?? "",
            fromAddress: row.text("from_address") ?? "",
            preview: row.text("preview") ?? "",
            receivedAt: Date(timeIntervalSince1970: TimeInterval(receivedMs) / 1000),
            isUnread: !(row.bool("flags_seen") ?? false),
            isFlagged: row.bool("flags_flagged") ?? false,
            hasAttachment: row.bool("has_attachment") ?? false,
            labelKeys: labels
        )
    }

    static func encodeJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "[]"
    }

    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Insert payload

/// Wire-shape for upserting a header. Providers fill this out and hand it
/// to `MessageDAO.upsertHeader`. Keeping it as a struct rather than 27
/// arguments helps when adding new fields in V2.
struct HeaderUpsert: Sendable {
    var id: UUID
    var accountID: UUID
    var folderID: Int64
    var remoteUID: Int64
    var messageID: String?
    var threadID: String?
    var inReplyTo: String?
    var subject: String
    var fromName: String
    var fromAddress: String
    var toAddresses: [String]
    var ccAddresses: [String]
    var bccAddresses: [String]
    var replyTo: String?
    var preview: String
    var sentAt: Date
    var receivedAt: Date
    var sizeBytes: Int64?
    var flagsSeen: Bool
    var flagsFlagged: Bool
    var flagsAnswered: Bool
    var flagsDraft: Bool
    var hasAttachment: Bool
    var labelKeys: [String]

    init(
        id: UUID = UUID(),
        accountID: UUID,
        folderID: Int64,
        remoteUID: Int64,
        messageID: String? = nil,
        threadID: String? = nil,
        inReplyTo: String? = nil,
        subject: String,
        fromName: String = "",
        fromAddress: String,
        toAddresses: [String] = [],
        ccAddresses: [String] = [],
        bccAddresses: [String] = [],
        replyTo: String? = nil,
        preview: String = "",
        sentAt: Date,
        receivedAt: Date,
        sizeBytes: Int64? = nil,
        flagsSeen: Bool = false,
        flagsFlagged: Bool = false,
        flagsAnswered: Bool = false,
        flagsDraft: Bool = false,
        hasAttachment: Bool = false,
        labelKeys: [String] = []
    ) {
        self.id = id
        self.accountID = accountID
        self.folderID = folderID
        self.remoteUID = remoteUID
        self.messageID = messageID
        self.threadID = threadID
        self.inReplyTo = inReplyTo
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
        self.ccAddresses = ccAddresses
        self.bccAddresses = bccAddresses
        self.replyTo = replyTo
        self.preview = preview
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.sizeBytes = sizeBytes
        self.flagsSeen = flagsSeen
        self.flagsFlagged = flagsFlagged
        self.flagsAnswered = flagsAnswered
        self.flagsDraft = flagsDraft
        self.hasAttachment = hasAttachment
        self.labelKeys = labelKeys
    }
}
