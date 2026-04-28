import CoreFoundation
import Foundation
import Network

// File renamed from QQMailService.swift on 2026-04-28 (Phase 3.A5)
// once POP3 support was retired. Contents are now provider-agnostic
// shared types used by both `IMAPClient` (Phase 3.A2) and the new
// `GenericIMAPAdapter`'s SMTP submission path:
//
// - `MailServiceError`        — error model surfaced to the UI
// - `SecureMailStreamClient`  — TLS-wrapped NWConnection actor
// - `ParsedRawMessage`        — local Sent-folder mirror payload
// - `MailTimestampFormatter`  — UI-facing date display helper
// - `RFC2822DateParser`       — date parsing for the formatter

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

    /// Read exactly `count` bytes of the wire stream. Used by the IMAP
    /// client to consume server-declared literal blocks (`{N}\r\n<N
    /// bytes>`) where line-oriented reading would mis-frame on CRLFs
    /// embedded in headers / bodies.
    func readBytes(count: Int) async throws -> Data {
        while buffer.count < count {
            try await readMore()
        }
        let chunk = buffer.subdata(in: 0..<count)
        buffer.removeSubrange(0..<count)
        return chunk
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

/// Output of the local Sent-folder mirror. Splits header from body so
/// the sync engine can hand them to the right repository plane.
struct ParsedRawMessage: Sendable {
    let header: MailMessage
    let body: MailMessageBody
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
        return displayValues(date: date)
    }

    /// Date-typed sibling — preferred for callers that already have a
    /// parsed `Date` (e.g. IMAP `INTERNALDATE` arrives as one). Avoids
    /// the round-trip through RFC 2822 string formatting.
    static func displayValues(date: Date) -> DisplayValue {
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

