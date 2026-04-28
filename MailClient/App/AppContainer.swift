import Foundation

/// Composition root.
///
/// `live` builds the production graph. `MailDatabase` is opened
/// synchronously here (init is sync — see `MailDatabase.swift`); migrations
/// run inside `AppState.bootstrap()` which already runs in an async task.
struct AppContainer {
    let database: MailDatabase
    let repository: any MailRepository
    let accountRepository: any MailAccountRepository
    let syncService: MailSyncEngine

    static let live: AppContainer = {
        // 1. Open the SQLite cache. Falls back to a tmp path if Application
        //    Support somehow can't be reached (sandbox edge case during
        //    dev).
        let dbURL: URL = {
            do { return try MailDatabase.defaultURL() }
            catch {
                MailClientLogger.storage.error("Falling back to tmp DB path: \(error.localizedDescription)")
                return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    .appendingPathComponent("mailstream.sqlite")
            }
        }()

        let database: MailDatabase
        do {
            database = try MailDatabase(url: dbURL)
        } catch {
            // Truly catastrophic: SQLite open failed. Re-throwing here
            // would prevent app launch, so we fail loudly and fall back
            // to an in-memory file.
            MailClientLogger.storage.error("MailDatabase open failed at \(dbURL.path): \(error.localizedDescription)")
            // :memory: is a special SQLite path → ephemeral DB.
            database = (try? MailDatabase(url: URL(fileURLWithPath: ":memory:")))!
        }

        let repository = MailStoreRepository(db: database)
        let accountRepository = MailStoreAccountRepository(db: database)

        let credentialsStore = MailAccountCredentialsStore()
        let adapterRegistry = MailProviderAdapterRegistry(
            [
                QQMailAdapter()
            ]
        )
        let accountService = MailAccountService(
            accountRepository: accountRepository,
            credentialsStore: credentialsStore,
            adapterRegistry: adapterRegistry
        )
        let syncService = MailSyncEngine(
            repository: repository,
            accountService: accountService
        )

        return AppContainer(
            database: database,
            repository: repository,
            accountRepository: accountRepository,
            syncService: syncService
        )
    }()

    @MainActor
    func makeAppState() -> AppState {
        AppState(
            database: database,
            repository: repository,
            syncService: syncService,
            initialMessages: []   // SQLite is the source of truth now
        )
    }
}
