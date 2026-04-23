import Foundation

struct InMemoryMailRepository: MailRepository {
    private let seedMessages: [MailMessage]

    init(seedMessages: [MailMessage]) {
        self.seedMessages = seedMessages
    }

    func loadMessages() -> [MailMessage] {
        seedMessages
    }
}
