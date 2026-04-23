import Foundation

enum Mailbox: String, CaseIterable, Identifiable, Sendable {
    case inbox = "Inbox"
    case starred = "Starred"
    case drafts = "Drafts"
    case sent = "Sent"
    case archive = "Archive"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .inbox:
            return "tray"
        case .starred:
            return "star"
        case .drafts:
            return "doc"
        case .sent:
            return "paperplane"
        case .archive:
            return "archivebox"
        }
    }
}

struct MailMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let mailbox: Mailbox
    let senderName: String
    let senderEmail: String
    let subject: String
    let preview: String
    let bodyHTML: String
    let receivedAt: Date
    let isRead: Bool

    init(
        id: UUID = UUID(),
        mailbox: Mailbox,
        senderName: String,
        senderEmail: String,
        subject: String,
        preview: String,
        bodyHTML: String,
        receivedAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.mailbox = mailbox
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.subject = subject
        self.preview = preview
        self.bodyHTML = bodyHTML
        self.receivedAt = receivedAt
        self.isRead = isRead
    }
}

extension MailMessage {
    static let samples: [MailMessage] = [
        MailMessage(
            mailbox: .inbox,
            senderName: "Acme Product",
            senderEmail: "team@acme.test",
            subject: "Welcome to MailClient",
            preview: "Project scaffold is ready for mailbox sync, compose flow, and settings.",
            bodyHTML: """
            <html>
              <body style="font-family: -apple-system; padding: 16px;">
                <h2>Welcome to MailClient</h2>
                <p>This placeholder message seeds the initial UI state.</p>
                <p>You can replace sample data with a real sync pipeline in <code>Core/Services</code>.</p>
              </body>
            </html>
            """,
            receivedAt: .now.addingTimeInterval(-3600),
            isRead: false
        ),
        MailMessage(
            mailbox: .drafts,
            senderName: "You",
            senderEmail: "me@example.com",
            subject: "Draft: Architecture Notes",
            preview: "Keep the SwiftUI layer thin and push platform details into Platform/macOS.",
            bodyHTML: """
            <html>
              <body style="font-family: -apple-system; padding: 16px;">
                <h2>Draft: Architecture Notes</h2>
                <p>Draft saving, thread context, and attachments can evolve inside the Compose feature.</p>
              </body>
            </html>
            """,
            receivedAt: .now.addingTimeInterval(-18_000),
            isRead: true
        ),
        MailMessage(
            mailbox: .sent,
            senderName: "You",
            senderEmail: "me@example.com",
            subject: "Platform bridge checklist",
            preview: "Web view rendering, keyboard shortcuts, and multi-window coordination belong in Platform.",
            bodyHTML: """
            <html>
              <body style="font-family: -apple-system; padding: 16px;">
                <h2>Platform bridge checklist</h2>
                <ul>
                  <li>Message HTML rendering</li>
                  <li>Window lifecycle control</li>
                  <li>AppKit command and shortcut integration</li>
                </ul>
              </body>
            </html>
            """,
            receivedAt: .now.addingTimeInterval(-86_400),
            isRead: true
        )
    ]
}
