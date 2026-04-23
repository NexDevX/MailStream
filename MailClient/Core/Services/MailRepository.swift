import Foundation

protocol MailRepository: Sendable {
    func loadMessages() async -> [MailMessage]
    func saveMessages(_ messages: [MailMessage]) async
    func appendMessage(_ message: MailMessage) async
}
