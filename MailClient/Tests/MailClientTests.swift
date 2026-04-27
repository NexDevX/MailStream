import Foundation
import Testing
@testable import MailStrea

@Test
func inMemoryRepositoryReturnsSeedMessages() async {
    let repository = InMemoryMailRepository(
        seedMessages: SeedMailboxData.messages,
        seedBodies: SeedMailboxData.bodies
    )
    #expect(await repository.loadMessages().count == SeedMailboxData.messages.count)
}

@Test
func inMemoryRepositoryServesSeedBodies() async {
    let repository = InMemoryMailRepository(
        seedMessages: SeedMailboxData.messages,
        seedBodies: SeedMailboxData.bodies
    )
    let head = SeedMailboxData.messages.first!
    let body = await repository.loadBody(messageID: head.id)
    #expect(body != nil)
    #expect(body?.paragraphs.isEmpty == false)
}

@MainActor
@Test
func appStateBootstrapsWithInitialSelection() {
    let repository = InMemoryMailRepository(
        seedMessages: SeedMailboxData.messages,
        seedBodies: SeedMailboxData.bodies
    )
    let accountRepository = FileBackedMailAccountRepository(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
    let credentialsStore = MailAccountCredentialsStore()
    let providerRegistry = MailProviderRegistry(providers: [QQMailProvider()])
    let accountService = MailAccountService(
        accountRepository: accountRepository,
        credentialsStore: credentialsStore,
        providerRegistry: providerRegistry
    )
    let syncService = MailSyncService(
        repository: repository,
        accountService: accountService
    )
    let state = AppState(
        repository: repository,
        syncService: syncService,
        initialMessages: SeedMailboxData.messages
    )

    #expect(state.messages.isEmpty == false)
    #expect(state.selectedMessageID == SeedMailboxData.messages.first?.id)
}

@Test
func bodyStoreCachesAndEvictsLRU() async {
    let repository = InMemoryMailRepository(
        seedMessages: SeedMailboxData.messages,
        seedBodies: SeedMailboxData.bodies
    )
    let store = MailMessageBodyStore(repository: repository, capacity: 2)

    // Three distinct ids, capacity 2 → first one should be evicted.
    let ids = SeedMailboxData.messages.prefix(3).map(\.id)
    for id in ids {
        _ = await store.body(for: id)
    }
    let stats = await store.stats
    #expect(stats.count == 2)
    #expect(stats.capacity == 2)
}
