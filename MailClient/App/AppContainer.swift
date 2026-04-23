import Foundation

struct AppContainer {
    let repository: any MailRepository
    let accountRepository: any MailAccountRepository
    let syncService: MailSyncService

    static let live: AppContainer = {
        let repository = FileBackedMailRepository(fallbackMessages: SeedMailboxData.messages)
        let accountRepository = FileBackedMailAccountRepository()
        let credentialsStore = MailAccountCredentialsStore()
        let providerRegistry = MailProviderRegistry(
            providers: [
                QQMailProvider()
            ]
        )
        let accountService = MailAccountService(
            accountRepository: accountRepository,
            credentialsStore: credentialsStore,
            providerRegistry: providerRegistry
        )
        let syncService = MailSyncService(
            repository: repository,
            accountService: accountService
        )

        return AppContainer(
            repository: repository,
            accountRepository: accountRepository,
            syncService: syncService
        )
    }()

    @MainActor
    func makeAppState() -> AppState {
        AppState(
            repository: repository,
            syncService: syncService,
            initialMessages: SeedMailboxData.messages
        )
    }
}
