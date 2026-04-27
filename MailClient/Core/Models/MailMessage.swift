import Foundation

// MARK: - Sidebar / inbox enums

enum SidebarItem: String, CaseIterable, Identifiable, Sendable, Codable {
    case allMail = "All Mail"
    case priority = "Priority"
    case drafts = "Drafts"
    case sent = "Sent"
    case trash = "Trash"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .allMail:  return "envelope.fill"
        case .priority: return "star.fill"
        case .drafts:   return "square.and.pencil"
        case .sent:     return "paperplane.fill"
        case .trash:    return "trash.fill"
        }
    }
}

enum InboxFilter: String, CaseIterable, Identifiable, Sendable, Codable {
    case inbox = "Inbox"
    case focused = "Focused"
    case archive = "Archive"

    var id: String { rawValue }
}

// MARK: - Attachment metadata
//
// Bytes live elsewhere (cache file or upcoming attachments table). The
// model carries only what the UI needs to render a chip and what the body
// store needs to find the data later.

struct MailAttachment: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    /// Optional inline cache hint — set by the parser when bytes were
    /// captured during fetch. May be nil if bytes were dropped to save
    /// memory; in that case the next fetch repopulates.
    var cachePath: String?

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        cachePath: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.cachePath = cachePath
    }

    var ext: String {
        guard let dot = filename.lastIndex(of: "."),
              filename.index(after: dot) < filename.endIndex
        else { return "FILE" }
        return String(filename[filename.index(after: dot)...]).uppercased()
    }

    var humanSize: String {
        if sizeBytes < 1024 { return "\(sizeBytes) B" }
        if sizeBytes < 1024 * 1024 { return String(format: "%.1f KB", Double(sizeBytes) / 1024) }
        return String(format: "%.1f MB", Double(sizeBytes) / 1024 / 1024)
    }
}

// MARK: - MailMessage (header / summary)
//
// Why split header from body?
//
// In a typical inbox, a single message body is a few KB to a few hundred KB
// (HTML mail with quoted history, embedded base64 inline images). Headers
// are ~500 B. The list view only needs headers, so keeping `[MailMessage]`
// in `@Published` storage with `bodyParagraphs` inline meant 5 000 cached
// emails could occupy 50–500 MB of resident RAM for content the user
// almost never reads.
//
// After this split:
// - `MailMessage` — what AppState publishes. Cheap. List view reads it.
// - `MailMessageBody` — what the detail view loads on selection from
//   `MailMessageBodyStore`. Single-message footprint is unbounded; LRU
//   cache caps total bodies in memory.
//
// Attachments stay on the header because they're metadata-only and the
// list could surface paperclip indicators in the future.

struct MailMessage: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let accountID: UUID?
    let sidebarItem: SidebarItem
    let inboxFilter: InboxFilter

    // From / to display
    let senderName: String
    let senderRole: String          // typically the address; may include @ form
    let recipientLine: String

    // Categorization
    let tag: String                 // legacy free-form label key
    let isPriority: Bool

    // Display content
    let subject: String
    let preview: String             // first ~140 chars of body, ASCII safe
    let timestampLabel: String      // "10:24" / "Apr 23"
    let relativeTimestamp: String   // long format for the detail header

    // Lightweight metadata
    let attachments: [MailAttachment]

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
        attachments: [MailAttachment] = []
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
        self.attachments = attachments
    }

    // Legacy on-disk caches may still carry body fields; we ignore them on
    // decode. `decodeIfPresent` keeps the type backwards-compatible.
    enum CodingKeys: String, CodingKey {
        case id, accountID, sidebarItem, inboxFilter, senderName, senderRole
        case recipientLine, tag, subject, preview, timestampLabel
        case relativeTimestamp, isPriority, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id                = try c.decode(UUID.self,        forKey: .id)
        self.accountID         = try c.decodeIfPresent(UUID.self, forKey: .accountID)
        self.sidebarItem       = try c.decode(SidebarItem.self,  forKey: .sidebarItem)
        self.inboxFilter       = try c.decode(InboxFilter.self,  forKey: .inboxFilter)
        self.senderName        = try c.decode(String.self,       forKey: .senderName)
        self.senderRole        = try c.decode(String.self,       forKey: .senderRole)
        self.recipientLine     = try c.decode(String.self,       forKey: .recipientLine)
        self.tag               = try c.decode(String.self,       forKey: .tag)
        self.subject           = try c.decode(String.self,       forKey: .subject)
        self.preview           = try c.decode(String.self,       forKey: .preview)
        self.timestampLabel    = try c.decode(String.self,       forKey: .timestampLabel)
        self.relativeTimestamp = try c.decode(String.self,       forKey: .relativeTimestamp)
        self.isPriority        = try c.decode(Bool.self,         forKey: .isPriority)
        self.attachments       = try c.decodeIfPresent([MailAttachment].self, forKey: .attachments) ?? []
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

// MARK: - MailMessageBody (detail content)
//
// Loaded on demand by `MailMessageBodyStore`. Never published as part of
// `AppState.messages`. The detail view observes `AppState.selectedBody`
// (or whatever surface the store offers) and renders skeleton-while-loading.

struct MailMessageBody: Hashable, Sendable, Codable {
    /// Plain-text rendering, broken into paragraphs.
    let paragraphs: [String]
    /// Optional rich HTML content. When present, the detail view renders
    /// this via WKWebView for visual fidelity (typography, embedded
    /// images, marketing layouts). The plaintext `paragraphs` stay as a
    /// safe fallback (and as the source for FTS / preview / search).
    let htmlBody: String?
    /// Optional AI-summary bullets for the reading pane card.
    let highlights: [String]
    /// Sign-off line if separable from the last paragraph.
    let closing: String

    init(
        paragraphs: [String],
        htmlBody: String? = nil,
        highlights: [String] = [],
        closing: String = ""
    ) {
        self.paragraphs = paragraphs
        self.htmlBody = htmlBody
        self.highlights = highlights
        self.closing = closing
    }

    /// Convenience for raw text → paragraphs split.
    static func make(text: String, htmlBody: String? = nil, highlights: [String] = [], closing: String = "") -> MailMessageBody {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return MailMessageBody(
            paragraphs: paragraphs.isEmpty ? (text.isEmpty ? [] : [text]) : paragraphs,
            htmlBody: htmlBody,
            highlights: highlights,
            closing: closing
        )
    }

    /// Empty placeholder used while a real body loads.
    static let empty = MailMessageBody(paragraphs: [], htmlBody: nil, highlights: [], closing: "")

    /// True when there's any visible content.
    var hasContent: Bool {
        paragraphs.isEmpty == false
            || closing.isEmpty == false
            || highlights.isEmpty == false
            || (htmlBody?.isEmpty == false)
    }

    /// Codable: keep the legacy field set decodable (htmlBody defaults to nil)
    /// so caches written before this change still load.
    enum CodingKeys: String, CodingKey {
        case paragraphs, htmlBody, highlights, closing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.paragraphs = try c.decode([String].self, forKey: .paragraphs)
        self.htmlBody   = try c.decodeIfPresent(String.self, forKey: .htmlBody)
        self.highlights = (try? c.decode([String].self, forKey: .highlights)) ?? []
        self.closing    = (try? c.decode(String.self,   forKey: .closing))    ?? ""
    }
}
