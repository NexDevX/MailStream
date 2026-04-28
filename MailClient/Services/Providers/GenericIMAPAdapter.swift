import Foundation

/// `MailProviderAdapter` implementation that speaks IMAP4rev1 (header
/// fetch + body fetch + flag update) and SMTP (send) using the
/// hand-rolled `IMAPClient` and the existing `SecureMailStreamClient`.
///
/// Stateless and `Sendable`: every method opens a fresh connection,
/// authenticates, runs, disconnects. This is intentionally simple for
/// Phase 3.A — connection pooling and pipelining belong in
/// `MailSyncEngine` (Phase 3.A4), not here. Concrete-provider tweaks
/// (e.g. QQ Mail) live in subclasses or wrapper structs that supply a
/// different `IMAPProviderConfig`.
///
/// **What it does not do (yet):**
/// - IDLE for push (capability flag exposes whether the server even
///   advertises it; Phase 3.C wires it up)
/// - APPEND on Sent — currently we leave a local-only Sent mirror;
///   pulling it from the server's Sent folder during the next sync
///   covers the common case
/// - CONDSTORE / QRESYNC for incremental sync — single-pass UID range
///   for now
struct GenericIMAPAdapter: MailProviderAdapter {

    let config: IMAPProviderConfig

    var providerType: MailProviderType { config.providerType }
    var capabilities: MailProviderCapabilities { config.capabilities }

    init(config: IMAPProviderConfig) {
        self.config = config
    }

    // MARK: - Connection

    func validateConnection(account: MailAccount, credentials: MailAccountCredentials) async throws {
        let client = IMAPClient(host: config.imapHost, port: config.imapPort)
        try await client.connect()
        defer { Task { await client.disconnect() } }
        try await client.login(username: credentials.normalizedEmailAddress, password: credentials.secret)
    }

    // MARK: - Folders

    func listFolders(account: MailAccount, credentials: MailAccountCredentials) async throws -> [RemoteFolder] {
        let client = IMAPClient(host: config.imapHost, port: config.imapPort)
        try await client.connect()
        defer { Task { await client.disconnect() } }
        try await client.login(username: credentials.normalizedEmailAddress, password: credentials.secret)
        let raw = try await client.listFolders()
        return raw.map { item in
            // `item.name` is the wire-format mailbox name (IMAP-UTF7
            // for non-ASCII). Keep that on `remoteID` so SELECT round-
            // trips byte-identically; decode for display + role guess.
            let decoded = IMAPResponseParser.decodeMailboxName(item.name)
            return RemoteFolder(
                remoteID: item.name,
                name: decoded,
                role: IMAPResponseParser.roleForAttributes(item.attributes, name: decoded),
                attributes: item.attributes
            )
        }
    }

    // MARK: - Headers

    func fetchHeaders(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        cursor: SyncCursor,
        limit: Int
    ) async throws -> FetchHeadersResult {
        let client = IMAPClient(host: config.imapHost, port: config.imapPort)
        try await client.connect()
        defer { Task { await client.disconnect() } }
        try await client.login(username: credentials.normalizedEmailAddress, password: credentials.secret)

        let summary = try await client.select(mailbox: folder.remoteID, examine: true)

        // UIDVALIDITY mismatch invalidates the cursor — the server has
        // renumbered. Fall back to a full top-of-mailbox window.
        let cursorUIDValidityChanged = cursor.uidValidity != nil && cursor.uidValidity != summary.uidValidity

        let range: String
        if cursor.lastUID > 0 && cursorUIDValidityChanged == false {
            // Incremental: anything strictly after the last seen UID.
            range = "\(cursor.lastUID + 1):*"
        } else if let next = summary.uidNext, next > 1 {
            // First sync: take the most recent `limit` UIDs.
            let lower = max(1, next - Int64(limit))
            range = "\(lower):\(next - 1)"
        } else {
            // Empty mailbox or server didn't advertise UIDNEXT.
            return FetchHeadersResult(
                headers: [],
                newCursor: SyncCursor(
                    lastUID: cursor.lastUID,
                    uidValidity: summary.uidValidity,
                    highestModseq: cursor.highestModseq,
                    lastFullSync: Date()
                ),
                totalMessages: summary.exists,
                unreadMessages: 0
            )
        }

        let items = try await client.uidFetchHeaders(range: range)
        let headers = items.compactMap { Self.makeRemoteHeader($0) }

        // Sort by sentAt desc as a stable contract for the sync engine.
        let sorted = headers.sorted { $0.sentAt > $1.sentAt }
        let newLastUID = items.compactMap(\.uid).max() ?? cursor.lastUID

        // Without SEARCH UNSEEN we can compute it from the FLAGS we
        // already received (within this batch). The sync engine will
        // refine the global unread count from local state.
        let unread = headers.filter { $0.flagsSeen == false }.count

        return FetchHeadersResult(
            headers: sorted,
            newCursor: SyncCursor(
                lastUID: max(newLastUID, cursor.lastUID),
                uidValidity: summary.uidValidity,
                highestModseq: cursor.highestModseq,
                lastFullSync: Date()
            ),
            totalMessages: summary.exists,
            unreadMessages: unread
        )
    }

    // MARK: - Body

    func fetchBody(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        remoteUID: Int64
    ) async throws -> RemoteBody {
        let client = IMAPClient(host: config.imapHost, port: config.imapPort)
        try await client.connect()
        defer { Task { await client.disconnect() } }
        try await client.login(username: credentials.normalizedEmailAddress, password: credentials.secret)
        _ = try await client.select(mailbox: folder.remoteID, examine: true)
        let raw = try await client.uidFetchBody(uid: remoteUID)

        let parsed = MIMEParser.parse(raw)
        let attachments = parsed.attachments.map {
            RemoteAttachment(
                filename: $0.filename,
                mimeType: $0.mimeType,
                sizeBytes: Int64($0.sizeBytes),
                contentID: $0.contentID,
                disposition: $0.disposition,
                data: nil  // TODO: fetch per-part on user click — Phase 3.B
            )
        }
        return RemoteBody(
            text: parsed.textBody.isEmpty ? nil : parsed.textBody,
            html: parsed.htmlBody,
            attachments: attachments
        )
    }

    // MARK: - Flags

    func updateFlags(
        account: MailAccount,
        credentials: MailAccountCredentials,
        folder: RemoteFolder,
        remoteUID: Int64,
        seen: Bool?,
        flagged: Bool?
    ) async throws {
        guard seen != nil || flagged != nil else { return }

        let client = IMAPClient(host: config.imapHost, port: config.imapPort)
        try await client.connect()
        defer { Task { await client.disconnect() } }
        try await client.login(username: credentials.normalizedEmailAddress, password: credentials.secret)
        _ = try await client.select(mailbox: folder.remoteID, examine: false)

        if let seen {
            try await client.uidStoreFlag(uid: remoteUID, flag: "\\Seen", set: seen)
        }
        if let flagged {
            try await client.uidStoreFlag(uid: remoteUID, flag: "\\Flagged", set: flagged)
        }
    }

    // MARK: - Send (SMTP)

    @discardableResult
    func send(
        message: OutgoingMailMessage,
        account: MailAccount,
        credentials: MailAccountCredentials
    ) async throws -> String? {
        try await SMTPSender.send(
            message: message,
            credentials: credentials,
            host: config.smtpHost,
            port: config.smtpPort
        )
    }

    // MARK: - Header decoding

    /// Turn an `IMAPResponseParser.FetchItem` into the wire `RemoteHeader`
    /// the sync engine consumes. Header bytes (from `BODY[HEADER]`) are
    /// fed through `MIMEParser` to handle MIME encoded-words, charsets,
    /// and address lists in one place.
    private static func makeRemoteHeader(_ item: IMAPResponseParser.FetchItem) -> RemoteHeader? {
        guard let uid = item.uid else { return nil }
        let headerData = item.headerLiteral ?? Data()
        let parsed = MIMEParser.parse(headerData)
        let headers = parsed.headers

        let subject = MIMEParser.decodeHeaderValue(headers["subject"] ?? "")
        let fromRaw = MIMEParser.decodeHeaderValue(headers["from"] ?? "")
        let toRaw = MIMEParser.decodeHeaderValue(headers["to"] ?? "")
        let ccRaw = MIMEParser.decodeHeaderValue(headers["cc"] ?? "")
        let dateRaw = headers["date"]
        let messageID = headers["message-id"].map { trimAngle($0) }
        let inReplyTo = headers["in-reply-to"].map { trimAngle($0) }
        let references = headers["references"].map { trimAngle($0) }
        // RFC 3501 has no thread-id; fall back to References for clients
        // that group by it. Real Gmail uses X-GM-THRID — Phase 3.B work.
        let threadID = references ?? inReplyTo

        let fromParsed = AddressLineParser.first(fromRaw)
        let toParsed = AddressLineParser.all(toRaw)
        let ccParsed = AddressLineParser.all(ccRaw)

        let sentAt: Date = item.internalDate
            ?? RFC2822DateParser.date(from: dateRaw ?? "")
            ?? Date(timeIntervalSince1970: 0)

        let flagsLower = Set(item.flags.map { $0.lowercased() })
        let seen = flagsLower.contains("\\seen")
        let flagged = flagsLower.contains("\\flagged")
        let answered = flagsLower.contains("\\answered")

        return RemoteHeader(
            remoteUID: uid,
            messageID: messageID,
            threadID: threadID,
            inReplyTo: inReplyTo,
            subject: subject.isEmpty ? "(No Subject)" : subject,
            fromName: fromParsed?.displayName ?? "",
            fromAddress: fromParsed?.address ?? "",
            toAddresses: toParsed.map(\.address),
            ccAddresses: ccParsed.map(\.address),
            preview: "",
            sentAt: sentAt,
            receivedAt: item.internalDate ?? sentAt,
            sizeBytes: item.sizeBytes,
            flagsSeen: seen,
            flagsFlagged: flagged,
            flagsAnswered: answered,
            // Without BODYSTRUCTURE we can't tell. Body fetch will set
            // the local attachment list directly; the cached header is
            // refreshed at that point.
            hasAttachment: false,
            labelKeys: []
        )
    }

    private static func trimAngle(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<") { value.removeFirst() }
        if value.hasSuffix(">") { value.removeLast() }
        return value
    }
}

// MARK: - Provider config

/// Per-provider knobs. `QQMailAdapter` etc. wrap a value of this struct
/// rather than subclassing `GenericIMAPAdapter` — adapters stay value
/// types and trivially `Sendable`.
struct IMAPProviderConfig: Sendable {
    let providerType: MailProviderType
    let imapHost: String
    let imapPort: Int
    let smtpHost: String
    let smtpPort: Int
    let capabilities: MailProviderCapabilities

    init(
        providerType: MailProviderType,
        imapHost: String,
        imapPort: Int = 993,
        smtpHost: String,
        smtpPort: Int = 465,
        capabilities: MailProviderCapabilities = []
    ) {
        self.providerType = providerType
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.capabilities = capabilities
    }
}

// MARK: - Address parsing

/// Local copy of address-line parsing (the QQMailService one is
/// `private`). Handles `"Display Name" <addr@host>` and a comma-
/// separated list. Tolerates malformed inputs by returning best-effort
/// values rather than throwing — header lists in the wild are messy.
private enum AddressLineParser {
    struct ParsedAddress: Sendable {
        let displayName: String
        let address: String
    }

    static func first(_ line: String) -> ParsedAddress? {
        all(line).first
    }

    static func all(_ line: String) -> [ParsedAddress] {
        guard line.isEmpty == false else { return [] }
        return splitTopLevel(line, separator: ",").compactMap(parseSingle)
    }

    private static func parseSingle(_ raw: String) -> ParsedAddress? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if let lo = trimmed.firstIndex(of: "<"),
           let hi = trimmed.firstIndex(of: ">"),
           lo < hi {
            let name = trimmed[..<lo]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let addr = String(trimmed[trimmed.index(after: lo)..<hi])
            return ParsedAddress(displayName: name, address: addr)
        }
        if trimmed.contains("@") {
            return ParsedAddress(displayName: trimmed, address: trimmed)
        }
        return ParsedAddress(displayName: trimmed, address: "")
    }

    /// Split on a separator that isn't inside `<...>` (and tolerate
    /// commas inside quoted display names — `"Last, First" <a@b>`).
    private static func splitTopLevel(_ line: String, separator: Character) -> [String] {
        var depthAngle = 0
        var inQuote = false
        var current = ""
        var parts: [String] = []
        for ch in line {
            if ch == "\"" { inQuote.toggle(); current.append(ch); continue }
            if ch == "<" && inQuote == false { depthAngle += 1; current.append(ch); continue }
            if ch == ">" && inQuote == false { depthAngle = max(0, depthAngle - 1); current.append(ch); continue }
            if ch == separator && depthAngle == 0 && inQuote == false {
                parts.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        if current.isEmpty == false { parts.append(current) }
        return parts
    }
}

// MARK: - SMTP

/// Minimal SMTP submission. Mirrors the existing flow in
/// `QQMailService.send` but lives here so the adapter is self-contained
/// and the legacy POP3 path can be deleted in Phase 3.A5 without
/// orphaning send.
private enum SMTPSender {
    @discardableResult
    static func send(
        message: OutgoingMailMessage,
        credentials: MailAccountCredentials,
        host: String,
        port: Int
    ) async throws -> String? {
        let recipients = sanitizedRecipients(from: message.to)
        guard recipients.isEmpty == false else {
            throw MailServiceError.unsupportedRecipient
        }

        let client = SecureMailStreamClient(host: host, port: port)
        try await client.connect()
        defer { Task { await client.close() } }

        let greeting = try await client.readLine()
        guard greeting.hasPrefix("220") else {
            throw MailServiceError.invalidServerResponse(greeting)
        }

        try await expect(client, "EHLO MailStrea.local", prefix: "250", multiline: true)
        try await expect(client, "AUTH LOGIN", prefix: "334")
        try await expect(client,
                         Data(credentials.normalizedEmailAddress.utf8).base64EncodedString(),
                         prefix: "334")
        let authResp = try await send(client, Data(credentials.secret.utf8).base64EncodedString())
        guard authResp.hasPrefix("235") else {
            if authResp.contains("535") { throw MailServiceError.authenticationFailed }
            throw MailServiceError.invalidServerResponse(authResp)
        }

        try await expect(client, "MAIL FROM:<\(credentials.normalizedEmailAddress)>", prefix: "250")
        for r in recipients {
            try await expect(client, "RCPT TO:<\(r)>", prefix: "250")
        }
        try await expect(client, "DATA", prefix: "354")
        try await client.writeData(makeMessage(
            from: credentials.normalizedEmailAddress,
            to: recipients,
            subject: message.subject,
            body: message.body
        ))
        let dataResp = try await client.readLine()
        guard dataResp.hasPrefix("250") else {
            throw MailServiceError.invalidServerResponse(dataResp)
        }
        try await expect(client, "QUIT", prefix: "221")
        // RFC 821 doesn't require the server to surface the assigned
        // Message-ID; QQ doesn't, so we return nil.
        return nil
    }

    private static func send(_ client: SecureMailStreamClient, _ command: String) async throws -> String {
        try await client.writeLine(command)
        return try await client.readLine()
    }

    private static func expect(
        _ client: SecureMailStreamClient,
        _ command: String,
        prefix: String,
        multiline: Bool = false
    ) async throws {
        try await client.writeLine(command)
        let response = multiline
            ? try await client.readSMTPMultilineResponse()
            : try await client.readLine()
        if response.hasPrefix(prefix) == false {
            if response.contains("535") { throw MailServiceError.authenticationFailed }
            throw MailServiceError.invalidServerResponse(response)
        }
    }

    private static func sanitizedRecipients(from recipients: [String]) -> [String] {
        recipients
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" }) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("@") && $0.isEmpty == false }
    }

    private static func makeMessage(from: String, to: [String], subject: String, body: String) -> Data {
        let encodedSubject = rfc2047Encoded(subject)
        let normalizedBody = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let escapedBody = normalizedBody
            .components(separatedBy: "\r\n")
            .map { $0.hasPrefix(".") ? ".\($0)" : String($0) }
            .joined(separator: "\r\n")

        let lines = [
            "From: \(from)",
            "To: \(to.joined(separator: ", "))",
            "Subject: \(encodedSubject)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: 8bit",
            "Date: \(rfc2822Date(Date()))",
            "",
            escapedBody,
            "."
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private static func rfc2047Encoded(_ value: String) -> String {
        guard value.canBeConverted(to: .ascii) == false else { return value }
        let encoded = Data(value.utf8).base64EncodedString()
        return "=?UTF-8?B?\(encoded)?="
    }

    private static func rfc2822Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: date)
    }
}

// MARK: - Date parsing

/// Local copy of the RFC 2822 date formats we accept. Matches the
/// reader in `QQMailService.swift` so behavior is consistent if the
/// `INTERNALDATE` is missing and we have to fall back to the `Date:`
/// header.
private enum RFC2822DateParser {
    static let formats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm Z"
    ]

    static func date(from value: String) -> Date? {
        guard value.isEmpty == false else { return nil }
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = format
            if let d = f.date(from: value) { return d }
        }
        return nil
    }
}
