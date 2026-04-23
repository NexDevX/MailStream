import Foundation

actor MailAccountService {
    private let accountRepository: any MailAccountRepository
    private let credentialsStore: MailAccountCredentialsStore
    private let providerRegistry: MailProviderRegistry

    init(
        accountRepository: any MailAccountRepository,
        credentialsStore: MailAccountCredentialsStore,
        providerRegistry: MailProviderRegistry
    ) {
        self.accountRepository = accountRepository
        self.credentialsStore = credentialsStore
        self.providerRegistry = providerRegistry
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

        let provider = try providerRegistry.provider(for: draft.providerType)
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
        try await provider.validateConnection(account: account, credentials: credentials)
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

    func provider(for account: MailAccount) throws -> any MailProvider {
        try providerRegistry.provider(for: account.providerType)
    }

    func isProviderAvailable(_ providerType: MailProviderType) -> Bool {
        providerRegistry.isAvailable(providerType)
    }

    func availableProviderTypes() -> [MailProviderType] {
        MailProviderType.allCases.filter { providerRegistry.isAvailable($0) }
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
