import Foundation

protocol MailProvider: Sendable {
    var providerType: MailProviderType { get }

    func validateConnection(account: MailAccount, credentials: MailAccountCredentials) async throws
    /// Fetch the most recent `limit` messages. Returns paired (header, body)
    /// so the sync engine can hand each plane to the right repository
    /// method. Adapters never write the DB themselves — separation of
    /// concerns: protocol parsing here, persistence upstream.
    func fetchInbox(account: MailAccount, credentials: MailAccountCredentials, limit: Int) async throws -> [ParsedRawMessage]
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
