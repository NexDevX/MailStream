import Foundation

/// Pure parsers for the subset of IMAP4rev1 untagged responses we need
/// for header-first sync. No I/O, no shared state — `IMAPClient` feeds
/// us already-assembled "logical lines" (literals inlined as text where
/// useful, or kept separate as a `Data` payload).
///
/// We deliberately do **not** implement a full RFC 3501 grammar:
/// - LIST: response shape is `* LIST (flags) "delim" name`
/// - SELECT: we only care about EXISTS, UIDVALIDITY, UIDNEXT
/// - FETCH (header sync): UID, FLAGS, INTERNALDATE, RFC822.SIZE,
///   BODY[HEADER] (returned as a literal data block, parsed by
///   `MIMEParser` upstream — IMAP only tells us *which* UID this header
///   belongs to)
/// - FETCH (body): same shape with BODY[] literal, again handed to
///   `MIMEParser` upstream
///
/// Anything we don't recognize is dropped, not erored — IMAP servers
/// commonly emit untagged responses we didn't ask for (EXPUNGE, FLAGS,
/// CAPABILITY in the middle of a session) and they must not abort sync.
enum IMAPResponseParser {

    // MARK: - Tagged completion

    /// Status of the tagged completion line `<tag> OK|NO|BAD <text>`.
    enum CompletionStatus: Equatable, Sendable { case ok, no, bad }

    struct Completion: Equatable, Sendable {
        let tag: String
        let status: CompletionStatus
        let text: String
    }

    static func parseCompletion(_ line: String) -> Completion? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let tag = String(parts[0])
        let status: CompletionStatus
        switch parts[1].uppercased() {
        case "OK":  status = .ok
        case "NO":  status = .no
        case "BAD": status = .bad
        default: return nil
        }
        let text = parts.count == 3 ? String(parts[2]) : ""
        return Completion(tag: tag, status: status, text: text)
    }

    // MARK: - LIST

    struct ListItem: Equatable, Sendable {
        let attributes: [String]
        let delimiter: String?
        let name: String
    }

    /// Parse `* LIST (\HasNoChildren \Sent) "/" "Sent Messages"` (any of
    /// the three fields can be quoted, NIL, or atom). Returns nil if the
    /// untagged line is not a LIST/LSUB.
    static func parseList(_ line: String) -> ListItem? {
        guard let body = stripUntaggedPrefix(line, keyword: "LIST") ?? stripUntaggedPrefix(line, keyword: "LSUB") else {
            return nil
        }
        var scanner = AtomScanner(body)
        guard let attrs = scanner.readParenList() else { return nil }
        let delimiter = scanner.readString()
        guard let name = scanner.readString() else { return nil }
        return ListItem(
            attributes: attrs,
            delimiter: (delimiter?.isEmpty ?? true) ? nil : delimiter,
            name: name
        )
    }

    /// Decode an IMAP-encoded mailbox name (RFC 3501 §5.1.3 — modified
    /// UTF-7) into UTF-8. ASCII-only names like `INBOX` pass through
    /// unchanged. QQ Mail returns names like `&UXZO1mWHTvZZOQ-` for
    /// custom Chinese folders; this function turns them back into
    /// readable text for the UI.
    ///
    /// We keep the original wire form on `RemoteFolder.remoteID` so
    /// `SELECT` / `EXAMINE` round-trip without any re-encoding work.
    /// Only `RemoteFolder.name` (display) goes through this decoder.
    ///
    /// Encoding rules being inverted:
    /// - Printable ASCII (0x20–0x7E) except `&` represents itself
    /// - `&-` represents the literal `&`
    /// - Anything else is encoded between `&` and `-` as the base64
    ///   form of the UTF-16BE bytes, with `,` substituting for `/` and
    ///   no `=` padding.
    static func decodeMailboxName(_ raw: String) -> String {
        // Fast path: nothing to decode if there's no `&`.
        guard raw.contains("&") else { return raw }

        var out = ""
        var i = raw.startIndex
        while i < raw.endIndex {
            let c = raw[i]
            if c != "&" {
                out.append(c)
                i = raw.index(after: i)
                continue
            }
            // Find the terminating `-`. RFC says encoded-word always
            // ends with `-`; if we don't find one, give up gracefully
            // and emit the raw substring.
            guard let end = raw[raw.index(after: i)...].firstIndex(of: "-") else {
                out.append(contentsOf: raw[i...])
                break
            }
            let payloadStart = raw.index(after: i)
            if payloadStart == end {
                // `&-` → literal `&`
                out.append("&")
            } else {
                let encoded = raw[payloadStart..<end]
                if let decoded = decodeBase64UTF16BE(String(encoded)) {
                    out.append(decoded)
                } else {
                    // Malformed payload — best-effort emit raw run so
                    // the user still sees *something* and we don't
                    // hide the folder.
                    out.append("&")
                    out.append(contentsOf: encoded)
                    out.append("-")
                }
            }
            i = raw.index(after: end)
        }
        return out
    }

    private static func decodeBase64UTF16BE(_ payload: String) -> String? {
        // Modified base64: `,` → `/`. No padding — pad to multiple of 4.
        var b64 = payload.replacingOccurrences(of: ",", with: "/")
        let mod = b64.count % 4
        if mod != 0 {
            b64.append(String(repeating: "=", count: 4 - mod))
        }
        guard let data = Data(base64Encoded: b64), data.count % 2 == 0 else {
            return nil
        }
        // UTF-16BE → String. Foundation has String(data:encoding:) for
        // .utf16BigEndian which does exactly this. We tolerate empty
        // payloads as the empty string (decoder is permissive on
        // server quirks).
        return String(data: data, encoding: .utf16BigEndian)
    }

    /// Map IMAP LIST `\Special-Use` attributes (or common QQ/Gmail folder
    /// names) onto our `MailFolderRole` enum. Falls back to .other.
    static func roleForAttributes(_ attributes: [String], name: String) -> MailFolderRole {
        let upperAttrs = Set(attributes.map { $0.uppercased() })
        if upperAttrs.contains("\\INBOX") { return .inbox }
        if upperAttrs.contains("\\SENT") || upperAttrs.contains("\\SENTMAIL") { return .sent }
        if upperAttrs.contains("\\DRAFTS") { return .drafts }
        if upperAttrs.contains("\\TRASH") || upperAttrs.contains("\\DELETED") { return .trash }
        if upperAttrs.contains("\\JUNK") || upperAttrs.contains("\\SPAM") { return .junk }
        if upperAttrs.contains("\\ARCHIVE") || upperAttrs.contains("\\ALL") { return .archive }
        if upperAttrs.contains("\\FLAGGED") || upperAttrs.contains("\\STARRED") { return .starred }
        if upperAttrs.contains("\\IMPORTANT") { return .important }

        // Fallback: guess from the visible name. QQ Mail returns
        // localized names like "已发送", "草稿箱", and English ones like
        // "Sent Messages" / "Drafts" depending on the locale.
        let upper = name.uppercased()
        if upper == "INBOX" { return .inbox }
        if upper.contains("SENT") || name.contains("已发送") || name.contains("发件") { return .sent }
        if upper.contains("DRAFT") || name.contains("草稿") { return .drafts }
        if upper.contains("TRASH") || upper.contains("DELETED") || name.contains("已删除") || name.contains("废件箱") { return .trash }
        if upper.contains("JUNK") || upper.contains("SPAM") || name.contains("垃圾") { return .junk }
        if upper.contains("ARCHIVE") || upper.contains("ALL MAIL") { return .archive }
        return .other
    }

    // MARK: - SELECT

    struct SelectSummary: Equatable, Sendable {
        var exists: Int = 0
        var recent: Int = 0
        var uidValidity: Int64?
        var uidNext: Int64?
    }

    /// Walk the untagged lines emitted between `<tag> SELECT box` and
    /// `<tag> OK [READ-WRITE] SELECT completed` to extract counts.
    static func parseSelect(lines: [String]) -> SelectSummary {
        var summary = SelectSummary()
        for line in lines {
            guard line.hasPrefix("* ") else { continue }
            let trimmed = line.dropFirst(2)
            // `* 18 EXISTS` / `* 2 RECENT`
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2, let count = Int(parts[0]) {
                let keyword = parts[1].uppercased()
                if keyword == "EXISTS" { summary.exists = count }
                else if keyword == "RECENT" { summary.recent = count }
            }
            // `* OK [UIDVALIDITY 3857529045] UIDs valid`
            if let bracket = bracketCode(in: String(trimmed)) {
                let codeParts = bracket.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard let head = codeParts.first?.uppercased() else { continue }
                if head == "UIDVALIDITY", codeParts.count == 2, let v = Int64(codeParts[1]) {
                    summary.uidValidity = v
                } else if head == "UIDNEXT", codeParts.count == 2, let v = Int64(codeParts[1]) {
                    summary.uidNext = v
                }
            }
        }
        return summary
    }

    // MARK: - FETCH header items

    /// One `* <seq> FETCH (...)` response, distilled to fields we care
    /// about. The literal payload (BODY[HEADER] or BODY[]) is delivered
    /// separately by the client.
    struct FetchItem: Equatable, Sendable {
        var sequenceNumber: Int
        var uid: Int64?
        var flags: [String] = []
        var internalDate: Date?
        var sizeBytes: Int64?
        var headerLiteral: Data?
        var bodyLiteral: Data?
    }

    // MARK: - FETCH atom parsing

    /// Parse the atom stream **between** the parens in `* <seq> FETCH (...)`.
    /// `body` is the textual portion with literal placeholders already
    /// substituted as `\u{1}<index>\u{1}` markers; `literals[index]` is
    /// the corresponding `Data` block. Using a sentinel avoids re-parsing
    /// raw literal data which may contain whitespace, parens, etc.
    static func parseFetchAtoms(
        sequenceNumber: Int,
        body: String,
        literals: [Data]
    ) -> FetchItem {
        var item = FetchItem(sequenceNumber: sequenceNumber)
        var scanner = AtomScanner(body)
        while let key = scanner.readAtom()?.uppercased() {
            switch key {
            case "UID":
                if let value = scanner.readAtom(), let uid = Int64(value) {
                    item.uid = uid
                }
            case "FLAGS":
                if let flags = scanner.readParenList() {
                    item.flags = flags
                }
            case "INTERNALDATE":
                if let raw = scanner.readString() {
                    item.internalDate = imapInternalDate(raw)
                }
            case "RFC822.SIZE":
                if let value = scanner.readAtom(), let size = Int64(value) {
                    item.sizeBytes = size
                }
            case "BODY[HEADER]", "BODY[HEADER.FIELDS]":
                if let data = scanner.readLiteral(literals: literals) {
                    item.headerLiteral = data
                }
            case "BODY[]", "RFC822":
                if let data = scanner.readLiteral(literals: literals) {
                    item.bodyLiteral = data
                }
            default:
                // Unknown atom: try to consume one value so the loop
                // can advance. If we can't, give up to avoid spinning.
                if scanner.consumeValue() == false { return item }
            }
        }
        return item
    }

    // MARK: - Private helpers

    private static func stripUntaggedPrefix(_ line: String, keyword: String) -> String? {
        // Untagged lines have shape `* <KEYWORD> <rest>`.
        guard line.hasPrefix("* ") else { return nil }
        let rest = line.dropFirst(2)
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].uppercased() == keyword else { return nil }
        return String(parts[1])
    }

    private static func bracketCode(in line: String) -> String? {
        // Find the first `[...]` in an OK / NO / BAD response.
        guard let lo = line.firstIndex(of: "["), let hi = line.firstIndex(of: "]"), lo < hi else {
            return nil
        }
        return String(line[line.index(after: lo)..<hi])
    }

    private static func imapInternalDate(_ raw: String) -> Date? {
        // RFC 3501 INTERNALDATE: `01-Jan-2026 12:34:56 +0000`
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        return formatter.date(from: raw)
    }
}

// MARK: - AtomScanner

/// Tiny tokenizer for the IMAP atom soup inside parens. Handles:
/// - bare atoms: `UID 12345`
/// - quoted strings: `"foo bar"` (with `\"` escape)
/// - paren lists: `(\Seen \Flagged)`
/// - `NIL`
/// - literal placeholders: a single byte `\u{1}` followed by the
///   ASCII index into the literals array, terminated by another `\u{1}`
///
/// It is line-oriented and not a full IMAP grammar. The strict subset is
/// what's emitted inside `* n FETCH (...)` and `* LIST ...`.
private struct AtomScanner {
    private let chars: [Character]
    private var index: Int = 0

    init(_ source: String) { self.chars = Array(source) }

    private var current: Character? { index < chars.count ? chars[index] : nil }

    private mutating func skipWhitespace() {
        while let c = current, c == " " || c == "\t" || c == "\r" || c == "\n" {
            index += 1
        }
    }

    mutating func readAtom() -> String? {
        skipWhitespace()
        guard let c = current else { return nil }
        if c == "(" || c == ")" { return nil }
        if c == "\"" { return readQuoted() }
        var out = ""
        while let ch = current, ch != " ", ch != "(", ch != ")", ch != "\t" {
            out.append(ch)
            index += 1
        }
        return out.isEmpty ? nil : out
    }

    /// Like `readAtom`, but unwraps quotes / `NIL` to empty string.
    /// LIST delimiter / LIST name come through here.
    mutating func readString() -> String? {
        skipWhitespace()
        guard let c = current else { return nil }
        if c == "\"" { return readQuoted() }
        if let atom = readAtom() {
            return atom == "NIL" ? "" : atom
        }
        return nil
    }

    mutating func readParenList() -> [String]? {
        skipWhitespace()
        guard current == "(" else { return nil }
        index += 1
        var items: [String] = []
        while true {
            skipWhitespace()
            if current == ")" { index += 1; return items }
            if current == nil { return items }
            if let s = readString() { items.append(s) } else { return items }
        }
    }

    private mutating func readQuoted() -> String? {
        guard current == "\"" else { return nil }
        index += 1
        var out = ""
        while let c = current {
            if c == "\\" {
                index += 1
                if let next = current { out.append(next); index += 1 }
                continue
            }
            if c == "\"" { index += 1; return out }
            out.append(c)
            index += 1
        }
        return out
    }

    /// Read a literal placeholder of the form `\u{1}<digits>\u{1}` and
    /// return the corresponding `Data` block. If the cursor isn't at a
    /// placeholder, returns nil and the caller can fall back to atom.
    mutating func readLiteral(literals: [Data]) -> Data? {
        skipWhitespace()
        guard current == "\u{1}" else { return nil }
        index += 1
        var digits = ""
        while let c = current, c != "\u{1}" {
            digits.append(c)
            index += 1
        }
        guard current == "\u{1}", let i = Int(digits), literals.indices.contains(i) else {
            return nil
        }
        index += 1
        return literals[i]
    }

    /// Best-effort skip past one value (atom, quoted, paren list, or
    /// literal). Returns false if nothing recognizable was found.
    mutating func consumeValue() -> Bool {
        skipWhitespace()
        guard let c = current else { return false }
        if c == "(" { _ = readParenList(); return true }
        if c == "\"" { _ = readQuoted(); return true }
        if c == "\u{1}" { _ = readLiteral(literals: []); return true }
        return readAtom() != nil
    }
}
