import Foundation

actor FileBackedMailAccountRepository: MailAccountRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cachedAccounts: [MailAccount]?

    init(fileURL: URL = FileBackedMailAccountRepository.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func loadAccounts() async -> [MailAccount] {
        if let cachedAccounts {
            return cachedAccounts
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let accounts = try decoder.decode([MailAccount].self, from: data)
            cachedAccounts = accounts
            return accounts
        } catch {
            cachedAccounts = []
            return []
        }
    }

    func saveAccounts(_ accounts: [MailAccount]) async {
        cachedAccounts = accounts

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(accounts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            MailClientLogger.storage.error("Failed to persist account repository: \(error.localizedDescription)")
        }
    }

    func upsertAccount(_ account: MailAccount) async {
        var accounts = await loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        await saveAccounts(accounts)
    }

    func deleteAccount(id: UUID) async {
        let accounts = await loadAccounts().filter { $0.id != id }
        await saveAccounts(accounts)
    }

    static func defaultFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("MailStrea", isDirectory: true)
            .appendingPathComponent("accounts.json", isDirectory: false)
    }
}
