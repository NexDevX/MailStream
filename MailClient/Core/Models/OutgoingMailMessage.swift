import Foundation

struct OutgoingMailMessage: Sendable {
    let to: [String]
    let subject: String
    let body: String
}
