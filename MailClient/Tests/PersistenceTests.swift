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
}
