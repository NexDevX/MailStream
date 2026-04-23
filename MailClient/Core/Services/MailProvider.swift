import Foundation

protocol MailProvider: Sendable {
    var providerType: MailProviderType { get }

    func validateConnection(account: MailAccount, credentials: MailAccountCredentials) async throws
    func fetchInbox(account: MailAccount, credentials: MailAccountCredentials, limit: Int) async throws -> [MailMessage]
    func send(message: OutgoingMailMessage, account: MailAccount, credentials: MailAccountCredentials) async throws
}

struct MailProviderRegistry: Sendable {
    private let providers: [MailProviderType: any MailProvider]

    init(providers: [any MailProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.providerType, $0) })
    }

    func provider(for providerType: MailProviderType) throws -> any MailProvider {
        guard let provider = providers[providerType] else {
            throw MailServiceError.providerNotAvailable(providerType)
        }
        return provider
    }

    func isAvailable(_ providerType: MailProviderType) -> Bool {
        providers[providerType] != nil
    }
}
