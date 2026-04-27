import Foundation

/// SQLite-backed implementation of `MailAccountRepository`.
/// Thin wrapper over `AccountDAO` — exists so the rest of the app keeps
/// talking to the protocol it always has.
actor MailStoreAccountRepository: MailAccountRepository {
    private let dao: AccountDAO

    init(db: MailDatabase) {
        self.dao = AccountDAO(db: db)
    }

    func loadAccounts() async -> [MailAccount] {
        do {
            return try await dao.all()
        } catch {
            MailClientLogger.storage.error("MailStoreAccountRepository.loadAccounts failed: \(error.localizedDescription)")
            return []
        }
    }

    func saveAccounts(_ accounts: [MailAccount]) async {
        for account in accounts {
            do {
                try await dao.upsert(account)
            } catch {
                MailClientLogger.storage.error("MailStoreAccountRepository.upsert failed: \(error.localizedDescription)")
            }
        }
    }

    func upsertAccount(_ account: MailAccount) async {
        do {
            try await dao.upsert(account)
        } catch {
            MailClientLogger.storage.error("MailStoreAccountRepository.upsertAccount failed: \(error.localizedDescription)")
        }
    }

    func deleteAccount(id: UUID) async {
        do {
            try await dao.remove(id: id)
        } catch {
            MailClientLogger.storage.error("MailStoreAccountRepository.deleteAccount failed: \(error.localizedDescription)")
        }
    }
}
