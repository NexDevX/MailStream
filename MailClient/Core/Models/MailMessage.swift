import Foundation

enum SidebarItem: String, CaseIterable, Identifiable, Sendable, Codable {
    case allMail = "All Mail"
    case priority = "Priority"
    case drafts = "Drafts"
    case sent = "Sent"
    case trash = "Trash"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .allMail:
            return "envelope.fill"
        case .priority:
            return "star.fill"
        case .drafts:
            return "square.and.pencil"
        case .sent:
            return "paperplane.fill"
        case .trash:
            return "trash.fill"
        }
    }
}

enum InboxFilter: String, CaseIterable, Identifiable, Sendable, Codable {
    case inbox = "Inbox"
    case focused = "Focused"
    case archive = "Archive"

    var id: String { rawValue }
}

struct MailMessage: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let accountID: UUID?
    let sidebarItem: SidebarItem
    let inboxFilter: InboxFilter
    let senderName: String
    let senderRole: String
    let recipientLine: String
    let tag: String
    let subject: String
    let preview: String
    let timestampLabel: String
    let relativeTimestamp: String
    let isPriority: Bool
    let bodyParagraphs: [String]
    let highlights: [String]
    let closing: String

    init(
        id: UUID = UUID(),
        accountID: UUID? = nil,
        sidebarItem: SidebarItem,
        inboxFilter: InboxFilter,
        senderName: String,
        senderRole: String,
        recipientLine: String,
        tag: String,
        subject: String,
        preview: String,
        timestampLabel: String,
        relativeTimestamp: String,
        isPriority: Bool,
        bodyParagraphs: [String],
        highlights: [String],
        closing: String
    ) {
        self.id = id
        self.accountID = accountID
        self.sidebarItem = sidebarItem
        self.inboxFilter = inboxFilter
        self.senderName = senderName
        self.senderRole = senderRole
        self.recipientLine = recipientLine
        self.tag = tag
        self.subject = subject
        self.preview = preview
        self.timestampLabel = timestampLabel
        self.relativeTimestamp = relativeTimestamp
        self.isPriority = isPriority
        self.bodyParagraphs = bodyParagraphs
        self.highlights = highlights
        self.closing = closing
    }
}

extension MailMessage {
    var senderInitials: String {
        senderName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }
}
