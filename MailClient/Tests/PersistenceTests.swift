import Foundation
import Testing
@testable import MailStrea

@Suite("Persistence")
struct PersistenceTests {

    /// Build a fresh DB on a unique tmp path so tests don't share state.
    /// Migrations are run via prepare(); each test starts at schema V1.
    private func makeDatabase() async throws -> MailDatabase {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mailstream-test-\(UUID().uuidString).sqlite")
        let db = try MailDatabase(url: url)
        try await db.prepare()
        return db
    }

    @Test
    func migrationCreatesAllTables() async throws {
        let db = try await makeDatabase()
        // Probe each user-data table by COUNT(*); any missing table throws.
        for table in ["accounts", "folders", "messages", "attachments", "sync_state", "drafts"] {
            let rows = try await db.sqlite.queryAll("SELECT COUNT(*) AS n FROM \(table)")
            #expect(rows.first?.int("n") == 0, "expected empty \(table) on fresh DB")
        }
        // schema_version has the migrated version recorded.
        let versionRows = try await db.sqlite.queryAll("SELECT MAX(version) AS v FROM schema_version")
        #expect(versionRows.first?.int("v") == 1)
    }

    @Test
    func accountUpsertRoundTrip() async throws {
        let db = try await makeDatabase()
        let dao = AccountDAO(db: db)

        let account = MailAccount(
            providerType: .qq,
            displayName: "Work",
            emailAddress: "alice@example.com",
            status: .connected,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isEnabled: true
        )

        try await dao.upsert(account)
        let loaded = try await dao.find(id: account.id)

        #expect(loaded?.emailAddress == "alice@example.com")
        #expect(loaded?.providerType == .qq)
        #expect(loaded?.displayName == "Work")
        #expect(loaded?.status == .connected)
        #expect(loaded?.isEnabled == true)
    }

    @Test
    func messageUpsertAndSummaryRoundTrip() async throws {
        let db = try await makeDatabase()
        let accountDAO = AccountDAO(db: db)
        let folderDAO = FolderDAO(db: db)
        let messageDAO = MessageDAO(db: db)

        let account = MailAccount(providerType: .qq, displayName: "A", emailAddress: "a@b.com")
        try await accountDAO.upsert(account)
        let folderID = try await folderDAO.upsert(
            accountID: account.id,
            remoteID: "INBOX",
            name: "Inbox",
            role: .inbox
        )

        let messageID = UUID()
        try await messageDAO.upsertHeader(HeaderUpsert(
            id: messageID,
            accountID: account.id,
            folderID: folderID,
            remoteUID: 42,
            subject: "Hello world",
            fromName: "Alice",
            fromAddress: "alice@example.com",
            toAddresses: ["a@b.com"],
            preview: "Just checking in.",
            sentAt: Date(timeIntervalSince1970: 1_700_000_000),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await messageDAO.storeBody(messageID: messageID, text: "Hi!\n\nFull body.", html: nil)

        let summaries = try await messageDAO.summaries(folderID: folderID)
        #expect(summaries.count == 1)
        #expect(summaries.first?.subject == "Hello world")
        #expect(summaries.first?.fromAddress == "alice@example.com")

        let body = try await messageDAO.body(messageID: messageID)
        #expect(body?.text == "Hi!\n\nFull body.")
    }

    @Test
    func ftsSearchFindsRecentlyIndexedMessage() async throws {
        let db = try await makeDatabase()
        let accountDAO = AccountDAO(db: db)
        let folderDAO  = FolderDAO(db: db)
        let messageDAO = MessageDAO(db: db)

        let account = MailAccount(providerType: .qq, displayName: "A", emailAddress: "a@b.com")
        try await accountDAO.upsert(account)
        let folderID = try await folderDAO.upsert(
            accountID: account.id,
            remoteID: "INBOX",
            name: "Inbox",
            role: .inbox
        )

        try await messageDAO.upsertHeader(HeaderUpsert(
            accountID: account.id,
            folderID: folderID,
            remoteUID: 1,
            subject: "Quarterly report",
            fromAddress: "ceo@example.com",
            preview: "Numbers attached",
            sentAt: Date(),
            receivedAt: Date()
        ))

        let hits = try await messageDAO.search("quarterly")
        #expect(hits.count == 1)
        #expect(hits.first?.subject == "Quarterly report")
    }

    /// End-to-end: write through MailStoreRepository and read back via the
    /// MailRepository protocol, exactly as AppState sees it.
    @Test
    func mailStoreRepositoryRoundTrip() async throws {
        let db = try await makeDatabase()
        let accountRepo = MailStoreAccountRepository(db: db)
        let messageRepo = MailStoreRepository(db: db)

        let account = MailAccount(providerType: .qq, displayName: "Work", emailAddress: "u@example.com")
        await accountRepo.upsertAccount(account)

        let message = MailMessage(
            id: UUID(),
            accountID: account.id,
            sidebarItem: .allMail,
            inboxFilter: .inbox,
            senderName: "Bot",
            senderRole: "bot@example.com",
            recipientLine: "to u@example.com",
            tag: "QQ",
            subject: "Persisted",
            preview: "preview line",
            timestampLabel: "10:00",
            relativeTimestamp: "2026-01-01 10:00",
            isPriority: false
        )
        await messageRepo.saveMessages([message])
        await messageRepo.storeBody(
            messageID: message.id,
            body: MailMessageBody(paragraphs: ["First", "Second"])
        )

        // Header round-trip: list view sees the cached header.
        let loaded = await messageRepo.loadMessages()
        #expect(loaded.count == 1)
        #expect(loaded.first?.subject == "Persisted")
        #expect(loaded.first?.attachments.isEmpty == true)

        // Body round-trip: detail view's lazy load returns the same paragraphs.
        let body = await messageRepo.loadBody(messageID: message.id)
        #expect(body?.paragraphs == ["First", "Second"])
    }

    /// Phase 3 A6 — the IMAP sync engine writes through the new
    /// `upsertRemoteHeaders` / `upsertFolders` path. This locks down
    /// the contract: real IMAP UIDs land on disk, the message gets
    /// composed back into the right `SidebarItem` based on its
    /// folder's role, and re-running the same upsert is idempotent.
    @Test
    func remoteHeaderUpsertPathRoundTrips() async throws {
        let db = try await makeDatabase()
        let accountRepo = MailStoreAccountRepository(db: db)
        let messageRepo = MailStoreRepository(db: db)

        let account = MailAccount(providerType: .qq, displayName: "Work", emailAddress: "u@example.com")
        await accountRepo.upsertAccount(account)

        // 1) Persist server folder list — Inbox + Sent. The wire-form
        //    Sent name simulates QQ's MUTF-7 encoding so we also cover
        //    the "remoteID stays in wire format" invariant.
        let remoteFolders = [
            RemoteFolder(remoteID: "INBOX",  name: "Inbox", role: .inbox),
            RemoteFolder(remoteID: "Sent Messages", name: "Sent", role: .sent)
        ]
        let persisted = await messageRepo.upsertFolders(remoteFolders, for: account)
        #expect(persisted.count == 2)
        #expect(persisted.contains { $0.role == .inbox })
        #expect(persisted.contains { $0.role == .sent })

        let inbox = persisted.first { $0.role == .inbox }!
        let sent  = persisted.first { $0.role == .sent }!

        // 2) Upsert two headers across two folders.
        let inboxHeader = RemoteHeader(
            remoteUID: 4711,
            messageID: "<m1@example.com>",
            subject: "Welcome",
            fromAddress: "alice@example.com",
            preview: "Hi there",
            sentAt: Date(timeIntervalSince1970: 1_700_000_000),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            flagsFlagged: true
        )
        let sentHeader = RemoteHeader(
            remoteUID: 1,
            messageID: "<m2@example.com>",
            subject: "Reply to a@b",
            fromAddress: "u@example.com",
            preview: "Thanks",
            sentAt: Date(timeIntervalSince1970: 1_700_000_500),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        await messageRepo.upsertRemoteHeaders([inboxHeader], folder: inbox, account: account)
        await messageRepo.upsertRemoteHeaders([sentHeader],  folder: sent,  account: account)

        // 3) Read back via the protocol — list view contract.
        let loaded = await messageRepo.loadMessages()
        #expect(loaded.count == 2)
        let loadedInbox = loaded.first { $0.subject == "Welcome" }
        let loadedSent  = loaded.first { $0.subject == "Reply to a@b" }
        #expect(loadedInbox?.sidebarItem == .allMail,
                "Inbox role should map to .allMail SidebarItem")
        #expect(loadedInbox?.isPriority == true,
                "isFlagged should round-trip into MailMessage.isPriority")
        #expect(loadedSent?.sidebarItem == .sent,
                "Sent role should map to .sent SidebarItem")

        // 4) listFolders surfaces both rows for the sidebar.
        let folders = await messageRepo.listFolders(for: account.id)
        #expect(folders.count == 2)
        #expect(folders.contains { $0.remoteID == "Sent Messages" })

        // 5) Idempotency — re-upserting the same header doesn't
        //    duplicate. SQLite's (account, folder, remote_uid) unique
        //    index does the work; this guards against a regression
        //    where someone adds a column to the conflict clause.
        await messageRepo.upsertRemoteHeaders([inboxHeader], folder: inbox, account: account)
        let loadedAfterReplay = await messageRepo.loadMessages()
        #expect(loadedAfterReplay.count == 2)
    }
}
