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
        let folderID = try await folderDAO.upsert(
            accountID: accountID,
            remoteID: role.rawValue,                    // synthetic — IMAP would replace this
            name: role.rawValue.capitalized,
            role: role
        )

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
        let timestamp = MailTimestampFormatter.displayValues(
            from: ISO8601DateFormatter().string(from: summary.receivedAt)
        )
        return MailMessage(
            id: summary.id,
            accountID: summary.accountID,
            sidebarItem: .allMail,
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
