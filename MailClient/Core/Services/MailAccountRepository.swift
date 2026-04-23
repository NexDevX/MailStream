import Foundation

protocol MailAccountRepository: Sendable {
    func loadAccounts() async -> [MailAccount]
    func saveAccounts(_ accounts: [MailAccount]) async
    func upsertAccount(_ account: MailAccount) async
    func deleteAccount(id: UUID) async
}
