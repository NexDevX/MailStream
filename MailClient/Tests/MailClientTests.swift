import Foundation
import Testing
@testable import MailStrea

@Test
func inMemoryRepositoryReturnsSeedMessages() async {
    let repository = InMemoryMailRepository(seedMessages: SeedMailboxData.messages)

    #expect(await repository.loadMessages().count == SeedMailboxData.messages.count)
}

@MainActor
@Test
func appStateBootstrapsWithInitialSelection() {
    let repository = InMemoryMailRepository(seedMessages: SeedMailboxData.messages)
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
