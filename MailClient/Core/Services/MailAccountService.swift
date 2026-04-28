import Foundation

actor MailAccountService {
    private let accountRepository: any MailAccountRepository
    private let credentialsStore: MailAccountCredentialsStore
    private let adapterRegistry: MailProviderAdapterRegistry

    init(
        accountRepository: any MailAccountRepository,
        credentialsStore: MailAccountCredentialsStore,
        adapterRegistry: MailProviderAdapterRegistry
    ) {
        self.accountRepository = accountRepository
        self.credentialsStore = credentialsStore
        self.adapterRegistry = adapterRegistry
    }

    func loadAccounts() async -> [MailAccount] {
        await accountRepository.loadAccounts()
    }

    func connectAccount(_ draft: MailAccountConnectionDraft) async throws -> MailAccount {
        let normalizedEmailAddress = draft.emailAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedEmailAddress.contains("@"), normalizedEmailAddress.isEmpty == false else {
            throw MailServiceError.invalidEmailAddress
        }

        let adapter = try adapterRegistry.adapter(for: draft.providerType)
        var account = MailAccount(
            providerType: draft.providerType,
            displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedEmailAddress : draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            emailAddress: normalizedEmailAddress,
            status: .syncing
        )

        let credentials = MailAccountCredentials(
            accountID: account.id,
            emailAddress: normalizedEmailAddress,
            secret: draft.secret
        )
        try await adapter.validateConnection(account: account, credentials: credentials)
        try await credentialsStore.saveCredentials(accountID: account.id, secret: draft.secret)

        account.status = .connected
        account.lastSyncedAt = Date()
        account.lastErrorMessage = nil
        await accountRepository.upsertAccount(account)
        return account
    }

    func removeAccount(id: UUID) async throws {
        try await credentialsStore.deleteCredentials(accountID: id)
        await accountRepository.deleteAccount(id: id)
    }

    func credentials(for account: MailAccount) async throws -> MailAccountCredentials {
        guard let credentials = try await credentialsStore.loadCredentials(for: account) else {
            throw MailServiceError.accountNotConfigured
        }
        return credentials
    }

    func adapter(for account: MailAccount) throws -> any MailProviderAdapter {
        try adapterRegistry.adapter(for: account.providerType)
    }

    func isProviderAvailable(_ providerType: MailProviderType) -> Bool {
        adapterRegistry.isAvailable(providerType)
    }

    func availableProviderTypes() -> [MailProviderType] {
        MailProviderType.allCases.filter { adapterRegistry.isAvailable($0) }
    }

    func markSyncSuccess(for accountID: UUID) async {
        guard var account = await accountRepository.loadAccounts().first(where: { $0.id == accountID }) else {
            return
        }

        account.status = .connected
        account.lastSyncedAt = Date()
        account.lastErrorMessage = nil
        await accountRepository.upsertAccount(account)
    }

    func markSyncFailure(for accountID: UUID, message: String) async {
        guard var account = await accountRepository.loadAccounts().first(where: { $0.id == accountID }) else {
            return
        }

        account.status = .error
        account.lastErrorMessage = message
        await accountRepository.upsertAccount(account)
    }
}
