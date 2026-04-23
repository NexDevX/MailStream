import Foundation

enum MailProviderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case qq
    case gmail
    case outlook
    case icloud
    case customIMAPSMTP

    var id: String { rawValue }
}

enum MailAccountConnectionStatus: String, Codable, Sendable {
    case disconnected
    case connected
    case syncing
    case error
}

struct MailAccount: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var providerType: MailProviderType
    var displayName: String
    var emailAddress: String
    var status: MailAccountConnectionStatus
    var lastSyncedAt: Date?
    var lastErrorMessage: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        providerType: MailProviderType,
        displayName: String,
        emailAddress: String,
        status: MailAccountConnectionStatus = .disconnected,
        lastSyncedAt: Date? = nil,
        lastErrorMessage: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.providerType = providerType
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.status = status
        self.lastSyncedAt = lastSyncedAt
        self.lastErrorMessage = lastErrorMessage
        self.isEnabled = isEnabled
    }
}

struct MailAccountCredentials: Equatable, Sendable {
    let accountID: UUID
    let emailAddress: String
    let secret: String

    var normalizedEmailAddress: String {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct MailAccountConnectionDraft: Sendable {
    let providerType: MailProviderType
    let displayName: String
    let emailAddress: String
    let secret: String
}
