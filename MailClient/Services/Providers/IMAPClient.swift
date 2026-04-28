import Foundation

/// A small, opinionated IMAP4rev1 client built on top of the existing
/// `SecureMailStreamClient` (NWConnection + TLS). Implements only the
/// command set the rest of the app needs:
///
/// - `LOGIN` / `LOGOUT`
/// - `CAPABILITY`
/// - `LIST "" "*"`
/// - `SELECT` / `EXAMINE`
/// - `UID FETCH <range> (UID FLAGS INTERNALDATE RFC822.SIZE BODY.PEEK[HEADER])`
/// - `UID FETCH <uid> (BODY.PEEK[])`
/// - `UID STORE <uid> +FLAGS|-FLAGS (...)`
///
/// Everything else (IDLE / CONDSTORE / MOVE / SEARCH / APPEND) is left to
/// later phases. Keeping the surface tight means the response parser
/// stays small and we can swap to `swift-nio-imap` later without
/// reshaping the call sites.
///
/// The parser handles IMAP literals (`{N}\r\n` followed by raw bytes)
/// by replacing each literal with a sentinel `\u{1}<index>\u{1}` token
/// in the textual line and stashing the bytes in a side array so the
/// `IMAPResponseParser` can resolve them without re-scanning bytes that
/// might contain CRLFs / parens / quotes.
actor IMAPClient {
    enum IMAPError: LocalizedError, Sendable {
        case greetingFailed(String)
        case commandFailed(command: String, status: IMAPResponseParser.CompletionStatus, text: String)
        case malformedResponse(String)
        case literalTooLarge(Int)

        var errorDescription: String? {
            switch self {
            case .greetingFailed(let line):
                return "IMAP 服务器问候异常：\(line)"
            case .commandFailed(let command, let status, let text):
                let label: String
                switch status {
                case .ok: label = "OK"
                case .no: label = "NO"
                case .bad: label = "BAD"
                }
                return "IMAP \(command) 失败（\(label)）：\(text)"
            case .malformedResponse(let line):
                return "IMAP 响应格式异常：\(line)"
            case .literalTooLarge(let size):
                return "IMAP 字面量过大（\(size) 字节）。"
            }
        }
    }

    /// Result of one tagged command, carrying every untagged response
    /// emitted before completion plus the per-line literals.
    struct CommandResult: Sendable {
        let untagged: [UntaggedLine]
        let completion: IMAPResponseParser.Completion
    }

    /// One untagged response (`* ...`). `text` already has literal
    /// placeholders substituted; raw bytes are in `literals` indexed
    /// by the placeholder.
    struct UntaggedLine: Sendable {
        let text: String
        let literals: [Data]
    }

    /// Cap a single literal at 32 MB. Real-world bodies + attachments
    /// rarely come close; anything above is almost certainly a server
    /// bug or a pathological message we'd rather refuse.
    private static let maxLiteralBytes = 32 * 1024 * 1024

    private let transport: SecureMailStreamClient
    private var tagCounter: Int = 0
    private var didConnect = false

    init(host: String, port: Int) {
        self.transport = SecureMailStreamClient(host: host, port: port)
    }

    // MARK: - Lifecycle

    func connect() async throws {
        guard didConnect == false else { return }
        try await transport.connect()
        didConnect = true
        let greeting = try await transport.readLine()
        // Server greeting is untagged: `* OK ...` (or `* PREAUTH`,
        // which is rare and means we can skip LOGIN — we don't bother
        // optimizing for it).
        guard greeting.hasPrefix("* OK") || greeting.hasPrefix("* PREAUTH") else {
            throw IMAPError.greetingFailed(greeting)
        }
    }

    func disconnect() async {
        if didConnect {
            // Best-effort LOGOUT, then tear down the socket regardless.
            _ = try? await sendCommand("LOGOUT")
        }
        await transport.close()
        didConnect = false
    }

    // MARK: - High-level commands

    func login(username: String, password: String) async throws {
        try await runCommand("LOGIN \(quoted(username)) \(quoted(password))",
                             logName: "LOGIN")
    }

    func capability() async throws -> Set<String> {
        let result = try await runCommand("CAPABILITY", logName: "CAPABILITY")
        var caps: Set<String> = []
        for line in result.untagged where line.text.uppercased().hasPrefix("* CAPABILITY ") {
            // `* CAPABILITY IMAP4rev1 STARTTLS AUTH=PLAIN ...`
            let tokens = line.text.dropFirst("* CAPABILITY ".count).split(separator: " ")
            for t in tokens { caps.insert(String(t).uppercased()) }
        }
        return caps
    }

    func listFolders() async throws -> [IMAPResponseParser.ListItem] {
        let result = try await runCommand(#"LIST "" "*""#, logName: "LIST")
        return result.untagged.compactMap { IMAPResponseParser.parseList($0.text) }
    }

    /// Open `mailbox` read/write. Use `examine: true` for read-only
    /// (preferred for header sync — doesn't reset \Recent, slightly
    /// less server-side state churn).
    @discardableResult
    func select(mailbox: String, examine: Bool = false) async throws -> IMAPResponseParser.SelectSummary {
        let verb = examine ? "EXAMINE" : "SELECT"
        let result = try await runCommand("\(verb) \(quoted(mailbox))", logName: verb)
        // SelectSummary parses the textual portion of each untagged line.
        return IMAPResponseParser.parseSelect(lines: result.untagged.map(\.text))
    }

    /// `UID FETCH <range> (UID FLAGS INTERNALDATE RFC822.SIZE BODY.PEEK[HEADER])`.
    /// `range` follows IMAP set syntax: `1:*` for all, `12345:67890`
    /// for a window, or comma-separated UIDs.
    func uidFetchHeaders(range: String) async throws -> [IMAPResponseParser.FetchItem] {
        let result = try await runCommand(
            "UID FETCH \(range) (UID FLAGS INTERNALDATE RFC822.SIZE BODY.PEEK[HEADER])",
            logName: "UID FETCH HEADER"
        )
        return result.untagged.compactMap(parseFetch)
    }

    /// `UID FETCH <uid> (BODY.PEEK[])`. Returns the full RFC 822 message
    /// bytes ready to feed to `MIMEParser.parse`.
    func uidFetchBody(uid: Int64) async throws -> Data {
        let result = try await runCommand(
            "UID FETCH \(uid) (UID FLAGS BODY.PEEK[])",
            logName: "UID FETCH BODY"
        )
        for line in result.untagged {
            if let item = parseFetch(line), let body = item.bodyLiteral {
                return body
            }
        }
        throw IMAPError.malformedResponse("BODY[] missing in UID FETCH response")
    }

    /// `UID STORE <uid> +FLAGS|-FLAGS (<flag>)`. Use `set: true` to
    /// add the flag, `false` to remove.
    func uidStoreFlag(uid: Int64, flag: String, set: Bool) async throws {
        let op = set ? "+FLAGS.SILENT" : "-FLAGS.SILENT"
        try await runCommand("UID STORE \(uid) \(op) (\(flag))", logName: "UID STORE")
    }

    // MARK: - Command transport

    @discardableResult
    private func runCommand(_ command: String, logName: String) async throws -> CommandResult {
        let result = try await sendCommand(command)
        switch result.completion.status {
        case .ok:
            return result
        case .no, .bad:
            throw IMAPError.commandFailed(
                command: logName,
                status: result.completion.status,
                text: result.completion.text
            )
        }
    }

    private func sendCommand(_ command: String) async throws -> CommandResult {
        tagCounter += 1
        let tag = String(format: "A%04d", tagCounter)
        try await transport.writeLine("\(tag) \(command)")

        var untagged: [UntaggedLine] = []

        while true {
            let (text, literals) = try await readLogicalLine()
            if text.hasPrefix("\(tag) ") {
                let completionLine = String(text.dropFirst(tag.count + 1))
                guard let parsed = IMAPResponseParser.parseCompletion("\(tag) \(completionLine)") else {
                    throw IMAPError.malformedResponse(text)
                }
                return CommandResult(untagged: untagged, completion: parsed)
            }
            // Continuation requests (`+ ...`) only appear during AUTH /
            // APPEND; we don't issue those today, so treat as untagged.
            untagged.append(UntaggedLine(text: text, literals: literals))
        }
    }

    /// Read one logical IMAP response line: as many physical CRLF-
    /// separated lines as it takes to consume every embedded literal
    /// `{N}\r\n<N bytes>`. The literal blocks become `\u{1}<index>\u{1}`
    /// markers in the returned text and `Data` entries in `literals`.
    private func readLogicalLine() async throws -> (String, [Data]) {
        var combined = ""
        var literals: [Data] = []

        while true {
            let line = try await transport.readLine()
            if let (prefix, count) = trailingLiteralCount(in: line) {
                if count > Self.maxLiteralBytes { throw IMAPError.literalTooLarge(count) }
                combined.append(prefix)
                let placeholder = "\u{1}\(literals.count)\u{1}"
                literals.append(try await transport.readBytes(count: count))
                combined.append(placeholder)
                continue   // server will continue the same logical line
            }
            combined.append(line)
            return (combined, literals)
        }
    }

    /// If `line` ends with ` {N}` (with N a positive integer), return
    /// `(prefix-without-count, N)`. Otherwise nil.
    private func trailingLiteralCount(in line: String) -> (String, Int)? {
        guard line.hasSuffix("}"), let openIndex = line.lastIndex(of: "{") else { return nil }
        let countSlice = line[line.index(after: openIndex)..<line.index(before: line.endIndex)]
        guard let count = Int(countSlice), count >= 0 else { return nil }
        return (String(line[..<openIndex]), count)
    }

    /// Pull a `* <seq> FETCH (...)` line apart into a `FetchItem`.
    private func parseFetch(_ line: UntaggedLine) -> IMAPResponseParser.FetchItem? {
        // `* 1 FETCH (UID 12 ...)`
        guard line.text.hasPrefix("* ") else { return nil }
        let body = line.text.dropFirst(2)
        let parts = body.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, parts[1].uppercased() == "FETCH",
              let seq = Int(parts[0]) else { return nil }
        let atomBlock = String(parts[2])
        // Strip outer parens.
        guard atomBlock.hasPrefix("("), atomBlock.hasSuffix(")") else { return nil }
        let inside = String(atomBlock.dropFirst().dropLast())
        return IMAPResponseParser.parseFetchAtoms(
            sequenceNumber: seq,
            body: inside,
            literals: line.literals
        )
    }

    private func quoted(_ value: String) -> String {
        // RFC 3501 quoted-string: escape `\` and `"`. For passwords with
        // `}` we'd need a literal, but QQ / Gmail / Outlook app passwords
        // don't include those. Document the limitation rather than
        // silently switch to literal mode, which would change the wire
        // shape and ricochet through testing.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
