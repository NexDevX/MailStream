import Foundation

protocol MailRepository: Sendable {
    func loadMessages() -> [MailMessage]
}
