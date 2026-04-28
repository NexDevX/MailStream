import Foundation

/// QQ Mail-specific configuration. Wraps `GenericIMAPAdapter` with the
/// IMAP/SMTP endpoints documented at:
/// https://service.mail.qq.com/cgi-bin/help?subtype=1&id=28&no=1001256
///
/// QQ Mail requires an "authorization code" (授权码) instead of the
/// account password — the account wizard already collects that into
/// `MailAccountCredentials.secret`.
struct QQMailAdapter: MailProviderAdapter {

    private let inner: GenericIMAPAdapter

    init() {
        // QQ Mail's IMAP advertises CONDSTORE, but the dialect quirks
        // (UIDVALIDITY changes when folders are renamed via web UI;
        // IDLE works but drops after ~10 minutes) are handled lazily
        // by the sync engine, not by capability flags. Leave the set
        // empty until we verify each capability end-to-end.
        self.inner = GenericIMAPAdapter(config: IMAPProviderConfig(
            providerType: .qq,
            imapHost: "imap.qq.com",
            imapPort: 993,
            smtpHost: "smtp.qq.com",
            smtpPort: 465,
            capabilities: []
        ))
    }

    var providerType: MailProviderType { inner.providerType }
    var capabilities: MailProviderCapabilities { inner.capabilities }

    func validateConnection(account: MailAccount, credentials: MailAccountCredentials) async throws {
        try await inner.validateConnection(account: account, credentials: credentials)
    }

    func listFolders(account: MailAccount, credentials: MailAccountCredentials) async throws -> [RemoteFolder] {
        try await inner.listFolders(account: account, credentials: credentials)
    }

    func fetchHeaders(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        cursor: SyncCursor,
        limit: Int
    ) async throws -> FetchHeadersResult {
        try await inner.fetchHeaders(
            account: account,
            credentials: credentials,
            folder: folder,
            cursor: cursor,
            limit: limit
        )
    }

    func fetchBody(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        remoteUID: Int64
    ) async throws -> RemoteBody {
        try await inner.fetchBody(
            account: account,
            credentials: credentials,
            folder: folder,
            remoteUID: remoteUID
        )
    }

    func send(
        message: OutgoingMailMessage,
        account: MailAccount,
        credentials: MailAccountCredentials
    ) async throws -> String? {
        try await inner.send(message: message, account: account, credentials: credentials)
    }

    func updateFlags(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        remoteUID: Int64,
        seen: Bool?,
        flagged: Bool?
    ) async throws {
        try await inner.updateFlags(
            account: account,
            credentials: credentials,
            folder: folder,
            remoteUID: remoteUID,
            seen: seen,
            flagged: flagged
        )
    }
}
