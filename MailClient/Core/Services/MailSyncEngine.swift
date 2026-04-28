import Foundation

/// Coordinates per-account sync against the new `MailProviderAdapter`
/// surface. Header-first: pulls UID-keyed envelopes via `fetchHeaders`,
/// translates to the UI's `MailMessage` shape, and persists through
/// `MailRepository`. Body fetch is **deferred** to selection time —
/// `bodyStore` (Phase 2) covers that, and we lazily warm a small
/// trailing window so the most recent N messages already have bodies
/// when the user opens the inbox.
///
/// **Why this isn't called `MailSyncService` anymore:** the file kept
/// the old name during Phase 2 because the implementation was still
/// the POP3-shaped `fetchInbox`-on-each-tick pattern. Phase 3.A4
/// inverts that — folders are listed, an Inbox-shaped folder is
/// resolved per provider, headers move via `fetchHeaders(cursor:)`.
/// The "engine" label matches `roadmap.md`'s vocabulary so newcomers
/// know which protocol it speaks.
///
/// **What still ships from Phase 2 land:** persistence still goes
/// through `MailRepository.saveMessages([MailMessage])`. Real
/// `remoteUID` / `messageID` round-tripping needs a parallel header
/// path on the repository (Phase 3.A6) that doesn't lossy-convert
/// through `MailMessage`. Until then the UI sees IMAP data and
/// **resyncs are correct** — duplicates collapse on the synthesized
/// folder/UID combo because `MessageDAO.upsertHeader` is idempotent
/// on `(account, folder, remote_uid)` — but cursors aren't yet
/// persisted. The cost is one extra `UID FETCH` window per launch,
/// which we accept until A6 lands.
actor MailSyncEngine {
    /// Hard cap on the headers a single `fetchHeaders` call returns.
    /// Server-side IMAP windows can be much larger, but our UI table
    /// renders ~50 rows per density / breakpoint without scrolling, and
    /// we don't yet have FTS indexing for cold rows. Bumping this just
    /// burns RAM in the snapshot.
    private static let headerWindowSize = 50

    /// Of the latest headers, eagerly fetch this many bodies during
    /// refresh. The UI feels instantaneous when the user clicks the
    /// top message; older messages cost one round-trip on first open
    /// (acceptable). Any change here should be measured against the
    /// `idle.io` device budget.
    private static let bodyPrefetchCount = 8

    private let repository: any MailRepository
    private let accountService: MailAccountService

    init(repository: any MailRepository, accountService: MailAccountService) {
        self.repository = repository
        self.accountService = accountService
    }

    func bootstrap() async {
        MailClientLogger.sync.info("Bootstrapping MailStream sync engine")
    }

    // MARK: - Account passthroughs (kept for AppState API stability)

    func loadAccounts() async -> [MailAccount] {
        await accountService.loadAccounts()
    }

    func connectAccount(_ draft: MailAccountConnectionDraft) async throws -> MailAccount {
        try await accountService.connectAccount(draft)
    }

    func removeAccount(id: UUID) async throws {
        try await accountService.removeAccount(id: id)
    }

    func isProviderAvailable(_ providerType: MailProviderType) async -> Bool {
        await accountService.isProviderAvailable(providerType)
    }

    func availableProviderTypes() async -> [MailProviderType] {
        await accountService.availableProviderTypes()
    }

    // MARK: - Refresh

    /// Pull the Inbox of every enabled account through its adapter.
    /// Returns the total header count delivered to the repository.
    @discardableResult
    func refreshAll() async throws -> Int {
        let accounts = await accountService.loadAccounts().filter(\.isEnabled)
        guard accounts.isEmpty == false else {
            throw MailServiceError.accountNotConfigured
        }

        var fetchedHeaders: [MailMessage] = []
        var bodyJobs: [BodyJob] = []
        var firstError: Error?

        for account in accounts {
            do {
                let credentials = try await accountService.credentials(for: account)
                let adapter = try await accountService.adapter(for: account)

                // 1) Folder enumeration — find the Inbox. Until Phase
                //    3.A6 we only sync that one folder; multi-folder
                //    sync is a fan-out at this exact point.
                let folders = try await adapter.listFolders(account: account, credentials: credentials)
                guard let inbox = folders.first(where: { $0.role == .inbox })
                    ?? folders.first(where: { $0.remoteID.uppercased() == "INBOX" }) else {
                    throw MailServiceError.invalidServerResponse("Inbox folder not found")
                }

                // 2) Header fetch. Cursor starts empty (full window of
                //    the most recent N) — A6 wires the persisted
                //    `SyncCursor`.
                let initialCursor = SyncCursor(lastUID: 0, uidValidity: nil, highestModseq: nil, lastFullSync: nil)
                let result = try await adapter.fetchHeaders(
                    account: account,
                    credentials: credentials,
                    folder: inbox,
                    cursor: initialCursor,
                    limit: Self.headerWindowSize
                )

                for remote in result.headers {
                    let message = Self.makeMailMessage(
                        from: remote,
                        account: account
                    )
                    fetchedHeaders.append(message)
                }

                // 3) Eager body window — only for the freshest few so
                //    the UX of "click newest, see content immediately"
                //    is preserved. Older messages get fetched on
                //    selection.
                let prefetchTargets = result.headers.prefix(Self.bodyPrefetchCount).map { remote in
                    BodyJob(
                        account: account,
                        credentials: credentials,
                        adapter: adapter,
                        folder: inbox,
                        remoteHeader: remote
                    )
                }
                bodyJobs.append(contentsOf: prefetchTargets)

                await accountService.markSyncSuccess(for: account.id)
            } catch {
                if firstError == nil { firstError = error }
                await accountService.markSyncFailure(for: account.id, message: error.localizedDescription)
            }
        }

        if fetchedHeaders.isEmpty, let firstError {
            throw firstError
        }

        // Header plane: rebuild the inbox snapshot, preserve local-only
        // items (drafts/sent that didn't come from the server). Same
        // pattern as the legacy service — keeps the contract with
        // `MailRepository.saveMessages` honest.
        let existingMessages = await repository.loadMessages()
        let localMessages = existingMessages.filter { $0.sidebarItem != .allMail }
        let sortedMessages = fetchedHeaders.sorted { $0.timestampLabel > $1.timestampLabel }
        await repository.saveMessages(sortedMessages + localMessages)

        // Body plane: serialize body fetches per account. IMAP doesn't
        // pipeline well across mailboxes anyway, and serial keeps the
        // memory headroom predictable for big multipart messages.
        for job in bodyJobs {
            do {
                let remoteBody = try await job.adapter.fetchBody(
                    account: job.account,
                    credentials: job.credentials,
                    folder: job.folder,
                    remoteUID: job.remoteHeader.remoteUID
                )
                let body = Self.makeMailMessageBody(from: remoteBody)
                let messageID = Self.synthesizeMessageID(for: job.remoteHeader, accountID: job.account.id)
                await repository.storeBody(messageID: messageID, body: body)
            } catch {
                MailClientLogger.sync.error("Body prefetch failed for UID \(job.remoteHeader.remoteUID): \(error.localizedDescription)")
            }
        }

        return fetchedHeaders.count
    }

    // MARK: - Send

    func send(_ message: OutgoingMailMessage, preferredAccountID: UUID?) async throws -> MailMessage {
        let accounts = await accountService.loadAccounts()
        let selectedAccount = accounts.first(where: { $0.id == preferredAccountID && $0.isEnabled })
            ?? accounts.first(where: { $0.isEnabled })

        guard let account = selectedAccount else {
            throw MailServiceError.accountNotConfigured
        }

        let credentials = try await accountService.credentials(for: account)
        let adapter = try await accountService.adapter(for: account)
        _ = try await adapter.send(message: message, account: account, credentials: credentials)

        // Mirror of the outgoing message in the local Sent folder.
        // Same approach as the legacy `MailSyncService` — IMAP APPEND
        // to the server's Sent folder is wished-for but not yet wired.
        let parsed = makeLocalSentMessage(message, account: account)
        await repository.appendMessage(parsed.header)
        await repository.storeBody(messageID: parsed.header.id, body: parsed.body)
        return parsed.header
    }

    // MARK: - Mapping

    /// Translate an adapter `RemoteHeader` to the UI `MailMessage` shape.
    /// We use the message's stable IMAP UID as the source for our local
    /// UUID so the same message yields the same `MailMessage.id` across
    /// resyncs — that keeps body-cache hits warm and avoids selection
    /// flicker on every refresh.
    static func makeMailMessage(from remote: RemoteHeader, account: MailAccount) -> MailMessage {
        let timestamp = MailTimestampFormatter.displayValues(date: remote.sentAt)
        let id = synthesizeMessageID(for: remote, accountID: account.id)
        let recipientLine: String = {
            if remote.toAddresses.isEmpty == false {
                return "to \(remote.toAddresses.joined(separator: ", "))"
            }
            return "to \(account.emailAddress)"
        }()
        let attachments: [MailAttachment] = []   // BODYSTRUCTURE pass not yet wired; populated on body fetch.

        return MailMessage(
            id: id,
            accountID: account.id,
            sidebarItem: .allMail,
            inboxFilter: .inbox,
            senderName: remote.fromName.isEmpty ? remote.fromAddress : remote.fromName,
            senderRole: remote.fromAddress,
            recipientLine: recipientLine,
            tag: account.providerType.shortTag,
            subject: remote.subject,
            preview: remote.preview,
            timestampLabel: timestamp.shortLabel,
            relativeTimestamp: timestamp.detailLabel,
            isPriority: remote.flagsFlagged,
            attachments: attachments
        )
    }

    static func makeMailMessageBody(from remote: RemoteBody) -> MailMessageBody {
        let plain = remote.text ?? ""
        let cleaned = plain
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return MailMessageBody(
            paragraphs: paragraphs,
            htmlBody: remote.html,
            highlights: [],
            closing: ""
        )
    }

    /// Deterministic UUID from `(accountID, remoteUID)`. v5-flavor: a
    /// SHA1 of the bytes folded into a 128-bit value. Two refreshes of
    /// the same IMAP message yield the same `MailMessage.id` so the
    /// header upsert is idempotent and selection state survives reloads.
    static func synthesizeMessageID(for remote: RemoteHeader, accountID: UUID) -> UUID {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: accountID.uuid) { buf in bytes.append(contentsOf: buf) }
        var uid = remote.remoteUID.bigEndian
        withUnsafeBytes(of: &uid) { buf in bytes.append(contentsOf: buf) }
        let hashed = SHA1.hash(Data(bytes))
        var uuidBytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                         UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
        withUnsafeMutableBytes(of: &uuidBytes) { buf in
            for i in 0..<min(16, hashed.count) { buf[i] = hashed[i] }
        }
        return UUID(uuid: uuidBytes)
    }

    // MARK: - Local Sent mirror

    /// Build a local Sent-folder mirror of an outgoing message. The
    /// header goes to the message list; body to the cache so reopening
    /// the thread doesn't surprise the user with an empty pane.
    private func makeLocalSentMessage(_ message: OutgoingMailMessage, account: MailAccount) -> ParsedRawMessage {
        let trimmedBody = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = trimmedBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let previewSource = paragraphs.first ?? trimmedBody
        let preview = previewSource.replacingOccurrences(of: "\n", with: " ").prefix(120)
        let now = Date()
        let timestamp = MailTimestampFormatter.displayValues(date: now)

        let header = MailMessage(
            accountID: account.id,
            sidebarItem: .sent,
            inboxFilter: .inbox,
            senderName: account.displayName,
            senderRole: account.emailAddress,
            recipientLine: "to \(message.to.joined(separator: ", "))",
            tag: account.providerType.shortTag,
            subject: message.subject.isEmpty ? "(No Subject)" : message.subject,
            preview: String(preview),
            timestampLabel: timestamp.shortLabel,
            relativeTimestamp: timestamp.detailLabel,
            isPriority: false
        )
        let body = MailMessageBody(
            paragraphs: paragraphs.isEmpty ? [trimmedBody] : paragraphs,
            highlights: [],
            closing: ""
        )
        return ParsedRawMessage(header: header, body: body)
    }
}

// MARK: - Body prefetch job

/// One pending body fetch. We materialize this during the header pass
/// and process it after the header transaction commits, so the user
/// can see the inbox repaint while bodies are still flowing in.
private struct BodyJob: @unchecked Sendable {
    let account: MailAccount
    let credentials: MailAccountCredentials
    let adapter: any MailProviderAdapter
    let folder: RemoteFolder
    let remoteHeader: RemoteHeader
}

// MARK: - SHA1 — minimal, dependency-free

/// 20-byte SHA-1 used for `synthesizeMessageID`. We don't link
/// `CryptoKit` from `Core/Services` to keep the module a clean Swift
/// package candidate. SHA-1 is fine here: the input space is small,
/// collision resistance isn't a security property — uniqueness across
/// `(accountID, UID)` pairs is.
private enum SHA1 {
    static func hash(_ data: Data) -> [UInt8] {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var msg = Array(data)
        let originalLength = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        var lengthBE = originalLength.bigEndian
        withUnsafeBytes(of: &lengthBE) { msg.append(contentsOf: $0) }

        var i = 0
        while i < msg.count {
            var w = [UInt32](repeating: 0, count: 80)
            for j in 0..<16 {
                let b0 = UInt32(msg[i + j*4])
                let b1 = UInt32(msg[i + j*4 + 1])
                let b2 = UInt32(msg[i + j*4 + 2])
                let b3 = UInt32(msg[i + j*4 + 3])
                w[j] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            }
            for j in 16..<80 {
                let v = w[j-3] ^ w[j-8] ^ w[j-14] ^ w[j-16]
                w[j] = (v << 1) | (v >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for j in 0..<80 {
                let f: UInt32, k: UInt32
                switch j {
                case 0...19:  f = (b & c) | ((~b) & d);              k = 0x5A827999
                case 20...39: f = b ^ c ^ d;                          k = 0x6ED9EBA1
                case 40...59: f = (b & c) | (b & d) | (c & d);        k = 0x8F1BBCDC
                default:      f = b ^ c ^ d;                          k = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[j]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            i += 64
        }

        var out: [UInt8] = []
        for v in [h0, h1, h2, h3, h4] {
            out.append(UInt8((v >> 24) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8(v & 0xFF))
        }
        return out
    }
}
