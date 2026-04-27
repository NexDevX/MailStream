import Foundation

actor FileBackedMailRepository: MailRepository {
    private let fileURL: URL
    private let fallbackMessages: [MailMessage]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cachedMessages: [MailMessage]?

    init(
        fileURL: URL = FileBackedMailRepository.defaultFileURL(),
        fallbackMessages: [MailMessage]
    ) {
        self.fileURL = fileURL
        self.fallbackMessages = fallbackMessages
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadMessages() async -> [MailMessage] {
        if let cachedMessages {
            return cachedMessages
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decodedMessages = try decoder.decode([MailMessage].self, from: data)
            cachedMessages = decodedMessages
            return decodedMessages
        } catch {
            cachedMessages = fallbackMessages
            return fallbackMessages
        }
    }

    func saveMessages(_ messages: [MailMessage]) async {
        cachedMessages = messages

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            MailClientLogger.storage.error("Failed to persist mail repository: \(error.localizedDescription)")
        }
    }

    func appendMessage(_ message: MailMessage) async {
        var currentMessages = await loadMessages()
        currentMessages.insert(message, at: 0)
        await saveMessages(currentMessages)
    }

    // FileBackedMailRepository is the legacy JSON-on-disk store, kept only
    // as a fallback. Body persistence isn't supported here — production
    // code uses `MailStoreRepository`.
    func loadBody(messageID: UUID) async -> MailMessageBody? { nil }
    func storeBody(messageID: UUID, body: MailMessageBody) async { /* no-op */ }

    static func defaultFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("MailStrea", isDirectory: true)
            .appendingPathComponent("mailbox.json", isDirectory: false)
    }
}
