import CoreFoundation
import Foundation
import Network

enum MailServiceError: LocalizedError, Sendable {
    case invalidEmailAddress
    case missingAuthorizationCode
    case accountNotConfigured
    case providerNotAvailable(MailProviderType)
    case unsupportedRecipient
    case connectionClosed
    case invalidServerResponse(String)
    case authenticationFailed
    case keychainFailure(OSStatus)
    case transportFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmailAddress:
            return "请输入有效的邮箱地址。"
        case .missingAuthorizationCode:
            return "请输入邮箱授权码或应用专用密码。"
        case .accountNotConfigured:
            return "请先在设置中配置一个可用邮箱账号。"
        case .providerNotAvailable(let providerType):
            return "\(providerType.displayName(language: .simplifiedChinese)) 连接器还没有实现。"
        case .unsupportedRecipient:
            return "请至少填写一个有效的收件人地址。"
        case .connectionClosed:
            return "邮件服务器提前关闭了连接。"
        case .invalidServerResponse(let response):
            return "邮件服务器返回了无法识别的响应：\(response)"
        case .authenticationFailed:
            return "邮箱登录失败，请确认已开启 POP3/SMTP 并使用授权码或应用专用密码。"
        case .keychainFailure(let status):
            return "无法访问系统钥匙串（\(status)）。"
        case .transportFailure(let message):
            return message
        }
    }
}

struct QQMailProvider: MailProvider {
    let providerType: MailProviderType = .qq

    private let receiveHost = "pop.qq.com"
    private let receivePort = 995
    private let sendHost = "smtp.qq.com"
    private let sendPort = 465

    func validateConnection(account: MailAccount, credentials: MailAccountCredentials) async throws {
        let client = SecureMailStreamClient(host: receiveHost, port: receivePort)
        try await client.connect()
        defer { Task { await client.close() } }

        let greeting = try await client.readLine()
        guard greeting.hasPrefix("+OK") else {
            throw MailServiceError.invalidServerResponse(greeting)
        }

        _ = try await sendPOP3(command: "USER \(credentials.normalizedEmailAddress)", client: client)
        _ = try await sendPOP3(command: "PASS \(credentials.secret)", client: client)
        _ = try await sendPOP3(command: "QUIT", client: client)
    }

    func fetchInbox(account: MailAccount, credentials: MailAccountCredentials, limit: Int) async throws -> [ParsedRawMessage] {
        let client = SecureMailStreamClient(host: receiveHost, port: receivePort)
        try await client.connect()
        defer { Task { await client.close() } }

        let greeting = try await client.readLine()
        guard greeting.hasPrefix("+OK") else {
            throw MailServiceError.invalidServerResponse(greeting)
        }

        _ = try await sendPOP3(command: "USER \(credentials.normalizedEmailAddress)", client: client)
        _ = try await sendPOP3(command: "PASS \(credentials.secret)", client: client)

        let statResponse = try await sendPOP3(command: "STAT", client: client)
        let messageCount = parsePOP3MessageCount(from: statResponse)
        guard messageCount > 0 else {
            _ = try await sendPOP3(command: "QUIT", client: client)
            return []
        }

        let startIndex = max(1, messageCount - limit + 1)
        var messages: [ParsedRawMessage] = []

        for messageIndex in stride(from: messageCount, through: startIndex, by: -1) {
            try await client.writeLine("RETR \(messageIndex)")
            let response = try await client.readLine()
            guard response.hasPrefix("+OK") else {
                throw MailServiceError.invalidServerResponse(response)
            }

            let rawMessage = try await client.readDotTerminatedBlock()
            if let parsed = RawInternetMessageParser.parse(
                rawMessage,
                account: account,
                fallbackMailboxAddress: credentials.normalizedEmailAddress
            ) {
                messages.append(parsed)
            }
        }

        _ = try await sendPOP3(command: "QUIT", client: client)
        return messages
    }

    func send(message: OutgoingMailMessage, account: MailAccount, credentials: MailAccountCredentials) async throws {
        let recipients = sanitizedRecipients(from: message.to)
        guard recipients.isEmpty == false else {
            throw MailServiceError.unsupportedRecipient
        }

        let client = SecureMailStreamClient(host: sendHost, port: sendPort)
        try await client.connect()
        defer { Task { await client.close() } }

        let greeting = try await client.readLine()
        guard greeting.hasPrefix("220") else {
            throw MailServiceError.invalidServerResponse(greeting)
        }

        _ = try await sendSMTP(command: "EHLO MailStrea.local", expectingPrefix: "250", client: client, multiline: true)
        _ = try await sendSMTP(command: "AUTH LOGIN", expectingPrefix: "334", client: client)
        _ = try await sendSMTP(
            command: Data(credentials.normalizedEmailAddress.utf8).base64EncodedString(),
            expectingPrefix: "334",
            client: client
        )
        let authResponse = try await sendSMTP(
            command: Data(credentials.secret.utf8).base64EncodedString(),
            expectingPrefix: nil,
            client: client
        )

        guard authResponse.hasPrefix("235") else {
            if authResponse.contains("535") {
                throw MailServiceError.authenticationFailed
            }
            throw MailServiceError.invalidServerResponse(authResponse)
        }

        _ = try await sendSMTP(
            command: "MAIL FROM:<\(credentials.normalizedEmailAddress)>",
            expectingPrefix: "250",
            client: client
        )

        for recipient in recipients {
            _ = try await sendSMTP(command: "RCPT TO:<\(recipient)>", expectingPrefix: "250", client: client)
        }

        _ = try await sendSMTP(command: "DATA", expectingPrefix: "354", client: client)
        let mimeMessage = SMTPMessageBuilder.makeMessage(
            from: credentials.normalizedEmailAddress,
            to: recipients,
            subject: message.subject,
            body: message.body
        )
        try await client.writeData(mimeMessage)
        let dataResponse = try await client.readLine()
        guard dataResponse.hasPrefix("250") else {
            throw MailServiceError.invalidServerResponse(dataResponse)
        }

        _ = try await sendSMTP(command: "QUIT", expectingPrefix: "221", client: client)
    }

    private func sendPOP3(command: String, client: SecureMailStreamClient) async throws -> String {
        try await client.writeLine(command)
        let response = try await client.readLine()
        if response.hasPrefix("-ERR") {
            if response.localizedCaseInsensitiveContains("auth") {
                throw MailServiceError.authenticationFailed
            }
            throw MailServiceError.invalidServerResponse(response)
        }
        return response
    }

    private func sendSMTP(
        command: String,
        expectingPrefix: String?,
        client: SecureMailStreamClient,
        multiline: Bool = false
    ) async throws -> String {
        try await client.writeLine(command)
        let response = multiline ? try await client.readSMTPMultilineResponse() : try await client.readLine()

        if let expectingPrefix, response.hasPrefix(expectingPrefix) == false {
            if response.contains("535") {
                throw MailServiceError.authenticationFailed
            }
            throw MailServiceError.invalidServerResponse(response)
        }

        return response
    }

    private func parsePOP3MessageCount(from response: String) -> Int {
        let components = response.split(separator: " ")
        guard components.count >= 2 else {
            return 0
        }
        return Int(components[1]) ?? 0
    }

    private func sanitizedRecipients(from recipients: [String]) -> [String] {
        recipients
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" }) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("@") && $0.isEmpty == false }
    }
}

actor SecureMailStreamClient {
    private let queue = DispatchQueue(label: "com.mailstrea.mail.stream")
    private let connection: NWConnection
    private var buffer = Data()

    init(host: String, port: Int) {
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true
        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)),
            using: parameters
        )
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: MailServiceError.transportFailure(error.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: MailServiceError.connectionClosed)
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    func writeLine(_ command: String) async throws {
        try await writeData(Data((command + "\r\n").utf8))
    }

    func writeData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: MailServiceError.transportFailure(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data([0x0d, 0x0a])) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? String(decoding: lineData, as: UTF8.self)
            }

            try await readMore()
        }
    }

    func readDotTerminatedBlock() async throws -> Data {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            if line == "." {
                break
            }

            if line.hasPrefix("..") {
                lines.append(String(line.dropFirst()))
            } else {
                lines.append(line)
            }
        }

        return Data(lines.joined(separator: "\r\n").utf8)
    }

    func readSMTPMultilineResponse() async throws -> String {
        var responseLines: [String] = []
        while true {
            let line = try await readLine()
            responseLines.append(line)

            guard line.count >= 4 else {
                break
            }

            let separatorIndex = line.index(line.startIndex, offsetBy: 3)
            if line[separatorIndex] == " " {
                break
            }
        }

        return responseLines.joined(separator: "\n")
    }

    func close() {
        connection.cancel()
    }

    private func readMore() async throws {
        let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: MailServiceError.transportFailure(error.localizedDescription))
                    return
                }

                if let data, data.isEmpty == false {
                    continuation.resume(returning: data)
                    return
                }

                if isComplete {
                    continuation.resume(throwing: MailServiceError.connectionClosed)
                } else {
                    continuation.resume(throwing: MailServiceError.transportFailure("邮件服务器没有返回数据。"))
                }
            }
        }

        buffer.append(chunk)
    }
}

private enum SMTPMessageBuilder {
    static func makeMessage(from: String, to: [String], subject: String, body: String) -> Data {
        let encodedSubject = rfc2047Encoded(subject)
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let escapedBody = normalizedBody
            .components(separatedBy: "\r\n")
            .map { line in
                line.hasPrefix(".") ? ".\(line)" : String(line)
            }
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
        guard value.canBeConverted(to: .ascii) == false else {
            return value
        }

        let encoded = Data(value.utf8).base64EncodedString()
        return "=?UTF-8?B?\(encoded)?="
    }

    private static func rfc2822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}

/// Output of the wire parser. Splits header from body so the sync engine
/// can hand them to the right repository plane.
struct ParsedRawMessage: Sendable {
    let header: MailMessage
    let body: MailMessageBody
}

private enum RawInternetMessageParser {
    /// Parse a full RFC 822 / 5322 message into our display model.
    /// Body extraction is delegated to `MIMEParser` so multipart, nested
    /// alternatives, charset decoding, base64/quoted-printable, and
    /// attachments are all handled in one place.
    static func parse(_ data: Data, account: MailAccount, fallbackMailboxAddress: String) -> ParsedRawMessage? {
        guard data.isEmpty == false else { return nil }

        let parsed = MIMEParser.parse(data)
        let headers = parsed.headers

        let senderField    = MIMEParser.decodeHeaderValue(headers["from"] ?? fallbackMailboxAddress)
        let recipientField = MIMEParser.decodeHeaderValue(headers["to"]   ?? fallbackMailboxAddress)
        let subject        = MIMEParser.decodeHeaderValue(headers["subject"] ?? "(No Subject)")
        let dateField      = headers["date"]

        let cleanBody = parsed.textBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let paragraphs = cleanBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let previewSource = paragraphs.first ?? cleanBody
        let preview = previewSource
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(140)

        let sender    = MailAddressParser.parse(senderField)
        let recipient = MailAddressParser.parse(recipientField)
        let timestamp = MailTimestampFormatter.displayValues(from: dateField)

        let attachments: [MailAttachment] = parsed.attachments.map {
            MailAttachment(
                filename: $0.filename,
                mimeType: $0.mimeType,
                sizeBytes: $0.sizeBytes,
                cachePath: nil
            )
        }

        let header = MailMessage(
            accountID: account.id,
            sidebarItem: .allMail,
            inboxFilter: .inbox,
            senderName: sender.displayName,
            senderRole: sender.address,
            recipientLine: "to \(recipient.displayNameOrAddress)",
            tag: account.providerType.shortTag,
            subject: subject.isEmpty ? "(No Subject)" : subject,
            preview: String(preview),
            timestampLabel: timestamp.shortLabel,
            relativeTimestamp: timestamp.detailLabel,
            isPriority: false,
            attachments: attachments
        )
        let body = MailMessageBody(
            paragraphs: paragraphs.isEmpty ? [] : paragraphs,
            // Pass HTML through so the detail view can render with style.
            // MIMEParser already picked the right text/html part out of any
            // multipart/alternative; if it's nil we fall back to plaintext.
            htmlBody: parsed.htmlBody,
            highlights: [],
            closing: ""
        )
        return ParsedRawMessage(header: header, body: body)
    }
}

private enum MailAddressParser {
    struct ParsedAddress {
        let displayName: String
        let address: String

        var displayNameOrAddress: String {
            displayName.isEmpty ? address : displayName
        }
    }

    static func parse(_ rawValue: String) -> ParsedAddress {
        let cleanedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleanedValue.firstIndex(of: "<"),
           let end = cleanedValue.firstIndex(of: ">"),
           start < end {
            let name = cleanedValue[..<start].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let address = String(cleanedValue[cleanedValue.index(after: start)..<end])
            let displayName = name.isEmpty ? address : name
            return ParsedAddress(displayName: displayName, address: address)
        }

        if cleanedValue.contains("@") {
            return ParsedAddress(displayName: cleanedValue, address: cleanedValue)
        }

        return ParsedAddress(displayName: cleanedValue, address: cleanedValue)
    }
}

enum MailTimestampFormatter {
    struct DisplayValue {
        let shortLabel: String
        let detailLabel: String
    }

    static func displayValues(from rawValue: String?) -> DisplayValue {
        guard let rawValue,
              let date = RFC2822DateParser.date(from: rawValue)
        else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let value = formatter.string(from: Date())
            return DisplayValue(shortLabel: value, detailLabel: value)
        }

        let shortFormatter = DateFormatter()
        shortFormatter.locale = Locale.current
        shortFormatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd"

        let detailFormatter = DateFormatter()
        detailFormatter.locale = Locale.current
        detailFormatter.dateStyle = .medium
        detailFormatter.timeStyle = .short

        return DisplayValue(
            shortLabel: shortFormatter.string(from: date),
            detailLabel: detailFormatter.string(from: date)
        )
    }
}

private enum RFC2822DateParser {
    static let formats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm Z"
    ]

    static func date(from value: String) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

private extension Data {
    func split(separator: Data) -> [Data] {
        guard separator.isEmpty == false else { return [self] }

        var chunks: [Data] = []
        var searchRange = startIndex..<endIndex
        var currentIndex = startIndex

        while let range = range(of: separator, options: [], in: searchRange) {
            chunks.append(subdata(in: currentIndex..<range.lowerBound))
            currentIndex = range.upperBound
            searchRange = currentIndex..<endIndex
        }

        chunks.append(subdata(in: currentIndex..<endIndex))
        return chunks
    }
}
