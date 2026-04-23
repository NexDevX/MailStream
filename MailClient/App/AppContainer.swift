import Foundation

struct AppContainer {
    let repository: any MailRepository
    let syncService: MailSyncService

    static let live = AppContainer(
        repository: InMemoryMailRepository(seedMessages: SeedMailboxData.messages),
        syncService: MailSyncService()
    )

    @MainActor
    func makeAppState() -> AppState {
        AppState(repository: repository)
    }
}
