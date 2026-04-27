import Foundation

/// Test-only repository that keeps everything in two dictionaries. Useful
/// for SwiftUI previews and isolated AppState construction in tests.
actor InMemoryMailRepository: MailRepository {
    private var messages: [MailMessage]
    private var bodies: [UUID: MailMessageBody]

    init(seedMessages: [MailMessage], seedBodies: [UUID: MailMessageBody] = [:]) {
        self.messages = seedMessages
        self.bodies = seedBodies
    }

    // MARK: - Header plane

    func loadMessages() async -> [MailMessage] {
        messages
    }

    func saveMessages(_ messages: [MailMessage]) async {
        self.messages = messages
    }

    func appendMessage(_ message: MailMessage) async {
        messages.insert(message, at: 0)
    }

    // MARK: - Body plane

    func loadBody(messageID: UUID) async -> MailMessageBody? {
        bodies[messageID]
    }

    func storeBody(messageID: UUID, body: MailMessageBody) async {
        bodies[messageID] = body
    }
}
