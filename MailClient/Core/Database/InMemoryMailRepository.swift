import Foundation

actor InMemoryMailRepository: MailRepository {
    private var messages: [MailMessage]

    init(seedMessages: [MailMessage]) {
        self.messages = seedMessages
    }

    func loadMessages() async -> [MailMessage] {
        messages
    }

    func saveMessages(_ messages: [MailMessage]) async {
        self.messages = messages
    }

    func appendMessage(_ message: MailMessage) async {
        messages.insert(message, at: 0)
    }
}
