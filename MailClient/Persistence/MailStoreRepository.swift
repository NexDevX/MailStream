import Foundation

/// SQLite-backed implementation of `MailRepository`.
///
/// Header plane writes go through a single `BEGIN IMMEDIATE`/`COMMIT`
/// transaction so a kill mid-sync can never leave half-written state.
///
/// Body plane is a separate path:
/// - `loadBody` does one SELECT.
/// - `storeBody` upserts the body columns and flips `body_loaded`.
///
/// Memory: this actor only caches **headers** (snapshot for fast repeated
/// reads). Bodies are explicitly *not* cached here — that responsibility
/// belongs to `MailMessageBodyStore` which has LRU semantics.
actor MailStoreRepository: MailRepository {
    private let db: MailDatabase
    private let messageDAO: MessageDAO
    private let accountDAO: AccountDAO
    private let folderDAO: FolderDAO

    /// Snapshot of the last `loadMessages()` result. Invalidated on every
    /// write. The list view re-reads this often (chip toggles, scope
    /// changes), and the snapshot avoids hitting SQLite repeatedly.
    private var headerSnapshot: [MailMessage]?

    init(db: MailDatabase) {
        self.db = db
        self.messageDAO = MessageDAO(db: db)
        self.accountDAO = AccountDAO(db: db)
        self.folderDAO  = FolderDAO(db: db)
    }

    // MARK: - Header plane

    func loadMessages() async -> [MailMessage] {
        if let headerSnapshot { return headerSnapshot }

        do {
            let accounts = try await accountDAO.all()
            guard accounts.isEmpty == false else {
                headerSnapshot = []
                return []
            }
            var rows: [MailMessage] = []
            for account in accounts {
                let summaries = try await messageDAO.summariesForAccount(account.id, limit: 500)
                rows.append(contentsOf: summaries.map { Self.compose(summary: $0, account: account) })
            }
            // Newest first — receivedAt is already encoded in relativeTimestamp
            // when going through MailTimestampFormatter, but the DAO already
            // returns sorted DESC. Stable sort by displayed timestamp.
            headerSnapshot = rows
            return rows
        } catch {
            MailClientLogger.storage.error("MailStoreRepository.loadMessages failed: \(error.localizedDescription)")
            return []
        }
    }

    func saveMessages(_ messages: [MailMessage]) async {
        headerSnapshot = nil
        let pairs: [(UUID, MailMessage)] = messages.compactMap { msg in
            msg.accountID.map { ($0, msg) }
        }
        guard pairs.isEmpty == false else { return }

        do {
            try await db.sqlite.exec("BEGIN IMMEDIATE")
            for (accountID, msg) in pairs {
                try await persistHeader(msg, accountID: accountID)
            }
            try await db.sqlite.exec("COMMIT")
        } catch {
            _ = try? await db.sqlite.exec("ROLLBACK")
            MailClientLogger.storage.error("MailStoreRepository.saveMessages failed: \(error.localizedDescription)")
        }
    }

    /// Drop the cached header snapshot so the next `loadMessages()`
    /// re-queries SQLite. Used after a destructive wipe of the DB.
    func invalidateCaches() async {
        headerSnapshot = nil
    }

    // MARK: - Folder plane (Phase 3 A6)

    func upsertFolders(_ folders: [RemoteFolder], for account: MailAccount) async -> [MailFolder] {
        // Folder write is small (handful of rows per account) so we
        // skip the explicit BEGIN/COMMIT — each upsert is its own
        // SQLite transaction and the cost is dominated by the LIST
        // round-trip that produced this list.
        var written: [MailFolder] = []
        for remote in folders {
            do {
                let id = try await folderDAO.upsert(
                    accountID: account.id,
                    remoteID: remote.remoteID,
                    name: remote.name,
                    role: remote.role,
                    attributes: remote.attributes
                )
                written.append(MailFolder(
                    id: id,
                    accountID: account.id,
                    remoteID: remote.remoteID,
                    name: remote.name,
                    role: remote.role,
                    unreadCount: 0,
                    totalCount: 0
                ))
            } catch {
                MailClientLogger.storage.error(
                    "upsertFolders(\(remote.remoteID)) failed: \(error.localizedDescription)"
                )
            }
        }
        return written
    }

    func listFolders(for accountID: UUID) async -> [MailFolder] {
        do {
            return try await folderDAO.all(accountID: accountID)
        } catch {
            MailClientLogger.storage.error("listFolders failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Phase 3 A6 — the IMAP sync engine’s primary write path.
    /// Writes a batch of provider-shaped headers into SQLite under
    /// **one** transaction so a kill mid-sync can’t leave half a
    /// folder visible. Drops the header snapshot afterwards so the UI
    /// re-queries on the next read.
    ///
    /// Idempotency comes from `MessageDAO.upsertHeader`'s
    /// `(account_id, folder_id, remote_uid)` unique key — re-syncing
    /// the same UIDs updates flags / preview in place rather than
    /// inserting duplicates.
    func upsertRemoteHeaders(_ headers: [RemoteHeader], folder: MailFolder, account: MailAccount) async {
        guard headers.isEmpty == false else { return }
        headerSnapshot = nil

        do {
            try await db.sqlite.exec("BEGIN IMMEDIATE")
            for remote in headers {
                let id = MailSyncEngine.synthesizeMessageID(for: remote, accountID: account.id)
                let upsert = HeaderUpsert(
                    id: id,
                    accountID: account.id,
                    folderID: folder.id,
                    remoteUID: remote.remoteUID,
                    messageID: remote.messageID,
                    threadID: remote.threadID,
                    inReplyTo: remote.inReplyTo,
                    subject: remote.subject,
                    fromName: remote.fromName,
                    fromAddress: remote.fromAddress,
                    toAddresses: remote.toAddresses,
                    ccAddresses: remote.ccAddresses,
                    bccAddresses: [],
                    replyTo: nil,
                    preview: remote.preview,
                    sentAt: remote.sentAt,
                    receivedAt: remote.receivedAt,
                    sizeBytes: remote.sizeBytes,
                    flagsSeen: remote.flagsSeen,
                    flagsFlagged: remote.flagsFlagged,
                    flagsAnswered: remote.flagsAnswered,
                    flagsDraft: folder.role == .drafts,
                    hasAttachment: remote.hasAttachment,
                    labelKeys: remote.labelKeys.isEmpty
                        ? [account.providerType.shortTag]
                        : remote.labelKeys
                )
                try await messageDAO.upsertHeader(upsert)
            }
            try await db.sqlite.exec("COMMIT")
        } catch {
            _ = try? await db.sqlite.exec("ROLLBACK")
            MailClientLogger.storage.error(
                "upsertRemoteHeaders(\(folder.remoteID), \(headers.count) rows) failed: \(error.localizedDescription)"
            )
        }
    }

    func appendMessage(_ message: MailMessage) async {
        headerSnapshot = nil
        guard let accountID = message.accountID else { return }
        do {
            try await persistHeader(message, accountID: accountID)
        } catch {
            MailClientLogger.storage.error("MailStoreRepository.appendMessage failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Body plane

    func loadBody(messageID: UUID) async -> MailMessageBody? {
        do {
            guard let row = try await messageDAO.body(messageID: messageID) else { return nil }
            return MailMessageBody.make(text: row.text ?? "", htmlBody: row.html)
        } catch {
            MailClientLogger.storage.error("MailStoreRepository.loadBody failed: \(error.localizedDescription)")
            return nil
        }
    }

    func storeBody(messageID: UUID, body: MailMessageBody) async {
        let text = body.paragraphs.joined(separator: "\n\n")
        do {
            try await messageDAO.storeBody(messageID: messageID, text: text, html: body.htmlBody)
        } catch {
            MailClientLogger.storage.error("MailStoreRepository.storeBody failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Header upsert

    private func persistHeader(_ message: MailMessage, accountID: UUID) async throws {
        let role: MailFolderRole = {
            switch message.sidebarItem {
            case .allMail, .priority: return .inbox
            case .drafts:             return .drafts
            case .sent:               return .sent
            case .trash:              return .trash
            }
        }()

        // Prefer an existing IMAP-listed folder of this role over
        // synthesizing a parallel one. This keeps the local Sent
        // mirror (`MailSyncEngine.send`) writing into the same row
        // the server's Sent fetch landed in, instead of producing two
        // Sent folders with `remote_id` "sent" + "Sent Messages".
        let folderID: Int64
        if let existing = try await folderDAO.find(accountID: accountID, role: role) {
            folderID = existing.id
        } else {
            folderID = try await folderDAO.upsert(
                accountID: accountID,
                remoteID: role.rawValue,                // synthetic fallback
                name: role.rawValue.capitalized,
                role: role
            )
        }

        let receivedAt = Self.parseDate(message.relativeTimestamp) ?? Date()
        let remoteUID = Int64(abs(message.id.hashValue) & 0x7fffffffffffffff)

        let header = HeaderUpsert(
            id: message.id,
            accountID: accountID,
            folderID: folderID,
            remoteUID: remoteUID,
            subject: message.subject,
            fromName: message.senderName,
            fromAddress: message.senderRole,
            toAddresses: Self.parseRecipients(message.recipientLine),
            preview: message.preview,
            sentAt: receivedAt,
            receivedAt: receivedAt,
            flagsFlagged: message.isPriority,
            flagsDraft: message.sidebarItem == .drafts,
            hasAttachment: message.attachments.isEmpty == false,
            labelKeys: [message.tag]
        )

        try await messageDAO.upsertHeader(header)
    }

    // MARK: - Decode

    /// Reconstruct a `MailMessage` (header) from a DAO summary + its account.
    private static func compose(summary: MailMessageSummary, account: MailAccount) -> MailMessage {
        let timestamp = MailTimestampFormatter.displayValues(date: summary.receivedAt)
        return MailMessage(
            id: summary.id,
            accountID: summary.accountID,
            sidebarItem: Self.sidebarItem(for: summary.folderRole),
            inboxFilter: .inbox,
            senderName: summary.fromName,
            senderRole: summary.fromAddress,
            recipientLine: "to \(account.emailAddress)",
            tag: summary.labelKeys.first ?? account.providerType.shortTag,
            subject: summary.subject.isEmpty ? "(No Subject)" : summary.subject,
            preview: summary.preview,
            timestampLabel: timestamp.shortLabel,
            relativeTimestamp: timestamp.detailLabel,
            isPriority: summary.isFlagged,
            attachments: []  // attachments table population comes with Phase 3
        )
    }

    // MARK: - Helpers

    /// Map the persisted folder role onto the user-facing
    /// `SidebarItem` enum the navigation chrome speaks. The enum is
    /// narrower than the role taxonomy — `archive` / `junk` /
    /// `important` / `starred` / `other` all collapse to `allMail`
    /// because the sidebar doesn't surface them yet (Workstream A6 +
    /// later). `priority` is *not* in this map: it's a virtual scope
    /// filtered from `allMail` by `isFlagged`, not a folder a row
    /// can live in.
    private static func sidebarItem(for role: MailFolderRole) -> SidebarItem {
        switch role {
        case .sent:           return .sent
        case .drafts:         return .drafts
        case .trash, .junk:   return .trash
        case .inbox, .archive, .important, .starred, .other:
            return .allMail
        }
    }

    private static func parseRecipients(_ recipientLine: String) -> [String] {
        let trimmed = recipientLine
            .replacingOccurrences(of: #"^to\s+"#, with: "", options: .regularExpression)
        return trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
    }

    private static func parseDate(_ relative: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: relative) { return d }

        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = rfc822.date(from: relative) { return d }

        let medium = DateFormatter()
        medium.dateStyle = .medium
        medium.timeStyle = .short
        return medium.date(from: relative)
    }
}
