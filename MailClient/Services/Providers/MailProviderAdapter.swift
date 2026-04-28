import Foundation

/// The adapter protocol every mail backend implements.
///
/// Design goals:
/// - **Header-first**: `fetchHeaders` returns lightweight summaries. Bodies
///   are fetched on demand via `fetchBody`. Cuts memory & bandwidth.
/// - **UID-keyed**: implementations expose a stable per-folder UID (IMAP
///   UID; for Graph/Gmail we synthesise one from `historyId`/`internalId`
///   so the cache layer stays uniform).
/// - **Capability flags** so the UI can hide features the provider can't do
///   (push, threads, server-side search, OAuth refresh).
/// - **Token-based pagination** rather than offsets — IMAP, Graph and Gmail
///   API all model "give me what's after X".
/// - **Pure**: adapters never write to the DB. The sync engine owns
///   persistence. Adapters are stateless and `Sendable`.
protocol MailProviderAdapter: Sendable {
    var providerType: MailProviderType { get }
    var capabilities: MailProviderCapabilities { get }

    /// Cheap probe: confirm the credentials work. Should be ≤ 2s.
    func validateConnection(account: MailAccount, credentials: MailAccountCredentials) async throws

    /// List the account's folders. Called rarely (on add + on user refresh).
    func listFolders(account: MailAccount, credentials: MailAccountCredentials) async throws -> [RemoteFolder]

    /// Fetch headers for a folder, optionally starting after a UID/cursor.
    /// `cursor.lastUID == 0` means full history (caller decides how much to keep).
    func fetchHeaders(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        cursor: SyncCursor,
        limit: Int
    ) async throws -> FetchHeadersResult

    /// Fetch a single message body (text + HTML if available).
    func fetchBody(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        remoteUID: Int64
    ) async throws -> RemoteBody

    /// Send an outgoing message. Returns the assigned Message-ID if known.
    @discardableResult
    func send(
        message: OutgoingMailMessage,
        account: MailAccount,
        credentials: MailAccountCredentials
    ) async throws -> String?

    /// Apply a flag change (read/flagged/delete) on the server.
    func updateFlags(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        remoteUID: Int64,
        seen: Bool?,
        flagged: Bool?
    ) async throws
}

// MARK: - Wire shapes

struct MailProviderCapabilities: OptionSet, Sendable {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }

    static let push           = MailProviderCapabilities(rawValue: 1 << 0)
    static let threads        = MailProviderCapabilities(rawValue: 1 << 1)
    static let serverSearch   = MailProviderCapabilities(rawValue: 1 << 2)
    static let oauthRefresh   = MailProviderCapabilities(rawValue: 1 << 3)
    static let condStore      = MailProviderCapabilities(rawValue: 1 << 4)  // IMAP CONDSTORE / Gmail historyId
    static let labels         = MailProviderCapabilities(rawValue: 1 << 5)  // gmail-style multi-label
}

struct RemoteFolder: Hashable, Sendable {
    let remoteID: String
    let name: String
    let role: MailFolderRole
    let attributes: [String]

    init(remoteID: String, name: String, role: MailFolderRole, attributes: [String] = []) {
        self.remoteID = remoteID
        self.name = name
        self.role = role
        self.attributes = attributes
    }
}

struct RemoteHeader: Sendable {
    let remoteUID: Int64
    let messageID: String?
    let threadID: String?
    let inReplyTo: String?
    let subject: String
    let fromName: String
    let fromAddress: String
    let toAddresses: [String]
    let ccAddresses: [String]
    let preview: String
    let sentAt: Date
    let receivedAt: Date
    let sizeBytes: Int64?
    let flagsSeen: Bool
    let flagsFlagged: Bool
    let flagsAnswered: Bool
    let hasAttachment: Bool
    let labelKeys: [String]

    init(
        remoteUID: Int64,
        messageID: String? = nil,
        threadID: String? = nil,
        inReplyTo: String? = nil,
        subject: String,
        fromName: String = "",
        fromAddress: String,
        toAddresses: [String] = [],
        ccAddresses: [String] = [],
        preview: String = "",
        sentAt: Date,
        receivedAt: Date,
        sizeBytes: Int64? = nil,
        flagsSeen: Bool = false,
        flagsFlagged: Bool = false,
        flagsAnswered: Bool = false,
        hasAttachment: Bool = false,
        labelKeys: [String] = []
    ) {
        self.remoteUID = remoteUID
        self.messageID = messageID
        self.threadID = threadID
        self.inReplyTo = inReplyTo
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddresses = toAddresses
        self.ccAddresses = ccAddresses
        self.preview = preview
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.sizeBytes = sizeBytes
        self.flagsSeen = flagsSeen
        self.flagsFlagged = flagsFlagged
        self.flagsAnswered = flagsAnswered
        self.hasAttachment = hasAttachment
        self.labelKeys = labelKeys
    }
}

struct RemoteBody: Sendable {
    let text: String?
    let html: String?
    let attachments: [RemoteAttachment]

    init(text: String?, html: String?, attachments: [RemoteAttachment] = []) {
        self.text = text
        self.html = html
        self.attachments = attachments
    }
}

struct RemoteAttachment: Sendable {
    let filename: String
    let mimeType: String
    let sizeBytes: Int64
    let contentID: String?
    let disposition: String?
    let data: Data?    // nil if downloaded lazily

    init(filename: String, mimeType: String, sizeBytes: Int64, contentID: String? = nil, disposition: String? = nil, data: Data? = nil) {
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentID = contentID
        self.disposition = disposition
        self.data = data
    }
}

struct FetchHeadersResult: Sendable {
    let headers: [RemoteHeader]
    let newCursor: SyncCursor
    let totalMessages: Int
    let unreadMessages: Int

    init(headers: [RemoteHeader], newCursor: SyncCursor, totalMessages: Int, unreadMessages: Int) {
        self.headers = headers
        self.newCursor = newCursor
        self.totalMessages = totalMessages
        self.unreadMessages = unreadMessages
    }
}

// MARK: - Registry

struct MailProviderAdapterRegistry: Sendable {
    private let adapters: [MailProviderType: any MailProviderAdapter]

    init(_ adapters: [any MailProviderAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.providerType, $0) })
    }

    func adapter(for type: MailProviderType) throws -> any MailProviderAdapter {
        guard let adapter = adapters[type] else {
            throw MailServiceError.providerNotAvailable(type)
        }
        return adapter
    }

    var availableProviders: [MailProviderType] {
        Array(adapters.keys)
    }

    func isAvailable(_ providerType: MailProviderType) -> Bool {
        adapters[providerType] != nil
    }
}
