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

    func fetchInbox(account: MailAccount, credentials: MailAccountCredentials, limit: Int) async throws -> [MailMessage] {
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
        var messages: [MailMessage] = []

        for messageIndex in stride(from: messageCount, through: startIndex, by: -1) {
            try await client.writeLine("RETR \(messageIndex)")
            let response = try await client.readLine()
            guard response.hasPrefix("+OK") else {
                throw MailServiceError.invalidServerResponse(response)
            }

            let rawMessage = try await client.readDotTerminatedBlock()
            if let parsedMessage = RawInternetMessageParser.parse(
                rawMessage,
                account: account,
                fallbackMailboxAddress: credentials.normalizedEmailAddress
            ) {
                messages.append(parsedMessage)
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

private enum RawInternetMessageParser {
    static func parse(_ data: Data, account: MailAccount, fallbackMailboxAddress: String) -> MailMessage? {
        let separator = Data("\r\n\r\n".utf8)
        let components = data.split(separator: separator)

        guard components.isEmpty == false else {
            return nil
        }

        let headerData = Data(components[0])
        let bodyData = components.count > 1 ? Data(components[1]) : Data()
        let headers = parseHeaders(from: headerData)

        let senderField = decodeHeaderValue(headers["from"] ?? fallbackMailboxAddress)
        let recipientField = decodeHeaderValue(headers["to"] ?? fallbackMailboxAddress)
        let subject = decodeHeaderValue(headers["subject"] ?? "(No Subject)")
        let contentType = headers["content-type"] ?? "text/plain; charset=utf-8"
        let transferEncoding = headers["content-transfer-encoding"] ?? "8bit"
        let dateField = headers["date"]

        let extractedBody = extractBody(
            contentType: contentType,
            transferEncoding: transferEncoding,
            data: bodyData
        )

        let cleanBody = extractedBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let paragraphs = cleanBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let previewSource = paragraphs.first ?? cleanBody
        let preview = previewSource.replacingOccurrences(of: "\n", with: " ").prefix(120)

        let sender = MailAddressParser.parse(senderField)
        let recipient = MailAddressParser.parse(recipientField)
        let timestamp = MailTimestampFormatter.displayValues(from: dateField)

        return MailMessage(
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
            bodyParagraphs: paragraphs.isEmpty ? ["(No body)"] : paragraphs,
            highlights: [],
            closing: ""
        )
    }

    private static func parseHeaders(from data: Data) -> [String: String] {
        let headerString = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let unfoldedLines = headerString
            .replacingOccurrences(of: "\r\n\t", with: " ")
            .replacingOccurrences(of: "\r\n ", with: " ")
            .components(separatedBy: "\r\n")

        var headers: [String: String] = [:]
        for line in unfoldedLines where line.isEmpty == false {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return headers
    }

    private static func decodeHeaderValue(_ value: String) -> String {
        guard value.contains("=?") else {
            return value
        }

        var decodedValue = value
        let pattern = #"=\?([^?]+)\?([BQbq])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed()
        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let charset = nsValue.substring(with: match.range(at: 1))
            let encoding = nsValue.substring(with: match.range(at: 2)).lowercased()
            let payload = nsValue.substring(with: match.range(at: 3))

            let replacement: String
            if encoding == "b", let data = Data(base64Encoded: payload) {
                replacement = decode(data: data, charset: charset)
            } else {
                replacement = decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "), charset: charset)
            }

            decodedValue = (decodedValue as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return decodedValue
    }

    private static func extractBody(contentType: String, transferEncoding: String, data: Data) -> String {
        if contentType.lowercased().contains("multipart/"),
           let boundary = extractBoundary(from: contentType),
           let multipartBody = extractMultipartBody(boundary: boundary, from: data) {
            return multipartBody
        }

        return decodeBody(data: data, transferEncoding: transferEncoding, contentType: contentType)
    }

    private static func extractMultipartBody(boundary: String, from data: Data) -> String? {
        let delimiter = "--\(boundary)"
        let bodyString = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let parts = bodyString.components(separatedBy: delimiter)

        var htmlCandidate: String?
        for part in parts {
            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPart.isEmpty == false, trimmedPart != "--" else { continue }

            let components = trimmedPart.components(separatedBy: "\r\n\r\n")
            guard components.count >= 2 else { continue }

            let headerSection = components[0]
            let bodySection = components.dropFirst().joined(separator: "\r\n\r\n")
            let headers = parseHeaders(from: Data(headerSection.utf8))
            let contentType = headers["content-type"] ?? "text/plain; charset=utf-8"
            let transferEncoding = headers["content-transfer-encoding"] ?? "8bit"
            let decodedBody = decodeBody(
                data: Data(bodySection.utf8),
                transferEncoding: transferEncoding,
                contentType: contentType
            )

            if contentType.lowercased().contains("text/plain") {
                return decodedBody
            }

            if contentType.lowercased().contains("text/html") {
                htmlCandidate = decodedBody
            }
        }

        return htmlCandidate
    }

    private static func decodeBody(data: Data, transferEncoding: String, contentType: String) -> String {
        let normalizedEncoding = transferEncoding.lowercased()
        let decodedData: Data

        switch normalizedEncoding {
        case "base64":
            decodedData = Data(base64Encoded: sanitizedBase64(data)) ?? data
        case "quoted-printable":
            decodedData = Data(decodeQuotedPrintableData(String(decoding: data, as: UTF8.self)))
        default:
            decodedData = data
        }

        let charset = extractCharset(from: contentType) ?? "utf-8"
        let text = decode(data: decodedData, charset: charset)
        if contentType.lowercased().contains("text/html") {
            return stripHTML(text)
        }

        return text
    }

    private static func sanitizedBase64(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private static func extractBoundary(from contentType: String) -> String? {
        extractParameter(named: "boundary", from: contentType)
    }

    private static func extractCharset(from contentType: String) -> String? {
        extractParameter(named: "charset", from: contentType)
    }

    private static func extractParameter(named parameterName: String, from contentType: String) -> String? {
        let parts = contentType.split(separator: ";")
        for part in parts {
            let components = part.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else { continue }
            if components[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == parameterName {
                return components[1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    private static func decode(data: Data, charset: String) -> String {
        if let encoding = stringEncoding(for: charset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }

        return String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }

    private static func stringEncoding(for charset: String) -> String.Encoding? {
        let name = charset.trimmingCharacters(in: .whitespacesAndNewlines) as CFString
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }

        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    private static func decodeQuotedPrintable(_ value: String, charset: String) -> String {
        let data = Data(decodeQuotedPrintableData(value))
        return decode(data: data, charset: charset)
    }

    private static func decodeQuotedPrintableData(_ value: String) -> [UInt8] {
        let scalars = Array(value.unicodeScalars)
        var bytes: [UInt8] = []
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "=",
               index + 2 < scalars.count,
               let byte = hexByte(high: scalars[index + 1], low: scalars[index + 2]) {
                bytes.append(byte)
                index += 3
            } else if scalar == "=", index + 1 < scalars.count,
                      scalars[index + 1] == "\r" || scalars[index + 1] == "\n" {
                index += 1
                while index < scalars.count, scalars[index] == "\r" || scalars[index] == "\n" {
                    index += 1
                }
            } else {
                bytes.append(contentsOf: String(scalar).utf8)
                index += 1
            }
        }

        return bytes
    }

    private static func hexByte(high: UnicodeScalar, low: UnicodeScalar) -> UInt8? {
        guard let highValue = hexValue(high), let lowValue = hexValue(low) else {
            return nil
        }
        return UInt8(highValue * 16 + lowValue)
    }

    private static func hexValue(_ scalar: UnicodeScalar) -> Int? {
        switch scalar {
        case "0"..."9":
            return Int(scalar.value - UnicodeScalar("0").value)
        case "A"..."F":
            return Int(scalar.value - UnicodeScalar("A").value + 10)
        case "a"..."f":
            return Int(scalar.value - UnicodeScalar("a").value + 10)
        default:
            return nil
        }
    }

    private static func stripHTML(_ html: String) -> String {
        let withoutLineBreaks = html
            .replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        let stripped = withoutLineBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum MailTimestampFormatter {
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
