import Foundation

/// Recursive RFC 5322 / 2045 MIME parser focused on extracting the *display
/// body* (best plain-text representation) and a flat attachment list.
///
/// What it does
/// - Splits headers / body once on the first `\r\n\r\n` (the common bug we
///   used to hit was splitting on every blank line, which truncated bodies).
/// - Walks the multipart tree:
///     · multipart/alternative → prefer text/plain, fall back to text/html
///     · multipart/mixed / multipart/related → recurse + collect attachments
/// - Decodes each part with its own `Content-Transfer-Encoding`
///   (base64 / quoted-printable / 7bit / 8bit / binary).
/// - Decodes header and body bytes using each part's `charset` (UTF-8,
///   GB2312, GBK, ISO-8859-*, Big5 — anything CFString knows).
///
/// What it doesn't do (yet)
/// - DKIM / signature validation (out of scope).
/// - Inline-image rewriting for HTML rendering — we only strip tags.
/// - S/MIME / PGP — passes through as opaque attachment.
enum MIMEParser {

    // MARK: - Public API

    struct Parsed {
        var headers: [String: String]
        var textBody: String
        var htmlBody: String?
        var attachments: [Attachment]
    }

    struct Attachment {
        var filename: String
        var mimeType: String
        var sizeBytes: Int
        var contentID: String?
        var disposition: String?
    }

    static func parse(_ raw: Data) -> Parsed {
        let (headerData, bodyData) = splitOnce(raw, separator: crlfcrlf) ?? splitOnce(raw, separator: lflf) ?? (raw, Data())
        let headers = parseHeaders(headerData)
        let part = Part(headers: headers, body: bodyData)
        var collector = Collector()
        walk(part, into: &collector)

        let bestText: String = {
            if let plain = collector.bestPlain, plain.isEmpty == false { return plain }
            if let html = collector.bestHtml { return stripHTML(html) }
            return ""
        }()

        return Parsed(
            headers: headers,
            textBody: bestText,
            htmlBody: collector.bestHtml,
            attachments: collector.attachments
        )
    }

    // MARK: - Internal types

    private struct Part {
        let headers: [String: String]
        let body: Data
    }

    private struct Collector {
        var bestPlain: String?
        var bestHtml: String?
        var attachments: [Attachment] = []
    }

    // MARK: - Walk

    private static func walk(_ part: Part, into collector: inout Collector) {
        let contentType = part.headers["content-type"] ?? "text/plain; charset=utf-8"
        let lower = contentType.lowercased()

        if lower.hasPrefix("multipart/") {
            guard let boundary = parameter("boundary", from: contentType) else { return }
            let isAlternative = lower.contains("multipart/alternative")
            let parts = splitMultipart(part.body, boundary: boundary)

            if isAlternative {
                // Pick best preview within this alternative group: text/plain
                // wins; the HTML sibling is kept as a fallback.
                var localPlain: String?
                var localHtml: String?
                for sub in parts {
                    let subType = (sub.headers["content-type"] ?? "text/plain").lowercased()
                    if subType.hasPrefix("multipart/") {
                        var nested = Collector()
                        walk(sub, into: &nested)
                        if localPlain == nil { localPlain = nested.bestPlain }
                        if localHtml  == nil { localHtml  = nested.bestHtml }
                        collector.attachments.append(contentsOf: nested.attachments)
                        continue
                    }
                    let decoded = decodedString(of: sub)
                    if subType.contains("text/plain") {
                        localPlain = localPlain ?? decoded
                    } else if subType.contains("text/html") {
                        localHtml = localHtml ?? decoded
                    }
                }
                if collector.bestPlain == nil, let localPlain { collector.bestPlain = localPlain }
                if collector.bestHtml  == nil, let localHtml  { collector.bestHtml  = localHtml }
            } else {
                // mixed / related / digest / report — recurse and accumulate.
                for sub in parts {
                    walk(sub, into: &collector)
                }
            }
            return
        }

        // Leaf part.
        let disposition = part.headers["content-disposition"]?.lowercased() ?? ""
        let filename = parameter("filename", from: part.headers["content-disposition"] ?? "")
            ?? parameter("name", from: contentType)
        let isAttachment = disposition.hasPrefix("attachment")
            || (filename != nil && lower.contains("text/") == false)

        if isAttachment {
            collector.attachments.append(Attachment(
                filename: decodeHeaderValue(filename ?? "untitled"),
                mimeType: lower.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "application/octet-stream",
                sizeBytes: decodedDataSize(of: part),
                contentID: part.headers["content-id"],
                disposition: disposition.split(separator: ";").first.map { String($0) }
            ))
            return
        }

        let decoded = decodedString(of: part)
        if lower.contains("text/plain") {
            if collector.bestPlain == nil { collector.bestPlain = decoded }
        } else if lower.contains("text/html") {
            if collector.bestHtml == nil { collector.bestHtml = decoded }
        }
    }

    // MARK: - Decode

    private static func decodedString(of part: Part) -> String {
        let charset = parameter("charset", from: part.headers["content-type"] ?? "") ?? "utf-8"
        let data = decodedData(of: part)
        return decode(data, charset: charset)
    }

    private static func decodedData(of part: Part) -> Data {
        let encoding = (part.headers["content-transfer-encoding"] ?? "8bit").lowercased().trimmingCharacters(in: .whitespaces)
        switch encoding {
        case "base64":
            let cleaned = String(decoding: part.body, as: UTF8.self)
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            return Data(base64Encoded: cleaned) ?? part.body
        case "quoted-printable":
            return decodeQuotedPrintable(part.body)
        default: // 7bit / 8bit / binary / unknown — passthrough
            return part.body
        }
    }

    private static func decodedDataSize(of part: Part) -> Int {
        decodedData(of: part).count
    }

    // MARK: - Header parsing

    static func parseHeaders(_ data: Data) -> [String: String] {
        // Header bytes are usually ASCII; non-ASCII header values are 2047-encoded.
        let raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        // Unfold continuation lines (start with whitespace).
        let unfolded = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\t", with: " ")
            .replacingOccurrences(of: "\n ",  with: " ")
        var out: [String: String] = [:]
        for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            out[key] = value
        }
        return out
    }

    /// Decode RFC 2047 encoded-words (`=?charset?B?xxx?=` / `=?charset?Q?xxx?=`).
    static func decodeHeaderValue(_ value: String) -> String {
        guard value.contains("=?") else { return value }
        let pattern = #"=\?([^?]+)\?([BQbq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsValue = value as NSString
        var result = value
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed()
        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let charset = nsValue.substring(with: match.range(at: 1))
            let encoding = nsValue.substring(with: match.range(at: 2)).lowercased()
            let payload = nsValue.substring(with: match.range(at: 3))
            let decodedText: String
            if encoding == "b", let data = Data(base64Encoded: payload) {
                decodedText = decode(data, charset: charset)
            } else {
                let qpData = decodeQuotedPrintable(Data(payload.replacingOccurrences(of: "_", with: " ").utf8))
                decodedText = decode(qpData, charset: charset)
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: decodedText)
        }
        // Spec: adjacent encoded words separated only by whitespace fold into one.
        return result.replacingOccurrences(of: "?= =?", with: "?==?")
                      .replacingOccurrences(of: "\r\n", with: " ")
    }

    static func decode(_ data: Data, charset: String) -> String {
        let trimmed = charset.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let cf = CFStringConvertIANACharSetNameToEncoding(trimmed as CFString)
        if cf != kCFStringEncodingInvalidId {
            let ns = CFStringConvertEncodingToNSStringEncoding(cf)
            if let s = String(data: data, encoding: String.Encoding(rawValue: ns)) { return s }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - Multipart split

    /// Split a multipart body on its boundary. Each result has its own
    /// header block and body, decoded as a fresh `Part`.
    private static func splitMultipart(_ body: Data, boundary: String) -> [Part] {
        // Boundaries are CRLF-prefixed except possibly the very first one
        // and the closing `--boundary--`. We work in bytes so binary
        // attachments survive intact.
        let openBytes  = Data("--\(boundary)".utf8)
        let closeBytes = Data("--\(boundary)--".utf8)

        var parts: [Part] = []
        var index = body.startIndex
        var positions: [Int] = []

        while index < body.endIndex {
            guard let range = body.range(of: openBytes, in: index..<body.endIndex) else { break }
            positions.append(range.lowerBound)
            index = range.upperBound
        }

        for i in 0..<positions.count {
            let start = positions[i]
            // Skip past `--boundary` and the optional CRLF after it.
            var afterBoundary = start + openBytes.count
            // Closing boundary marker → done.
            if afterBoundary + 2 <= body.endIndex {
                let twoBytes = body[afterBoundary..<min(afterBoundary + 2, body.endIndex)]
                if Data(twoBytes) == Data("--".utf8) { break }
            }
            // Skip CRLF / LF after the boundary line.
            while afterBoundary < body.endIndex,
                  body[afterBoundary] == 0x0D || body[afterBoundary] == 0x0A {
                afterBoundary += 1
            }

            let nextStart = (i + 1 < positions.count) ? positions[i + 1] : body.endIndex
            // Trim trailing CRLF before the next boundary line.
            var partEnd = nextStart
            while partEnd > afterBoundary,
                  partEnd - 1 >= body.startIndex,
                  body[partEnd - 1] == 0x0D || body[partEnd - 1] == 0x0A {
                partEnd -= 1
            }

            let chunk = body[afterBoundary..<partEnd]
            guard chunk.isEmpty == false else { continue }
            let chunkData = Data(chunk)

            if let (h, b) = splitOnce(chunkData, separator: crlfcrlf) ?? splitOnce(chunkData, separator: lflf) {
                parts.append(Part(headers: parseHeaders(h), body: b))
            } else {
                // No header block — treat the whole thing as text body.
                parts.append(Part(headers: ["content-type": "text/plain; charset=utf-8"], body: chunkData))
            }
        }

        // If we never saw a closing boundary the loop above just bails out.
        _ = closeBytes
        return parts
    }

    // MARK: - Helpers

    /// Split `data` into (lhs, rhs) on the FIRST occurrence of `separator`.
    /// Crucially we don't split on every occurrence — that's the bug that
    /// truncated bodies before this rewrite.
    static func splitOnce(_ data: Data, separator: Data) -> (Data, Data)? {
        guard let range = data.range(of: separator) else { return nil }
        let lhs = data.subdata(in: data.startIndex..<range.lowerBound)
        let rhs = data.subdata(in: range.upperBound..<data.endIndex)
        return (lhs, rhs)
    }

    static func parameter(_ name: String, from header: String) -> String? {
        // Walks "; key=value" pairs, tolerating quoted values and whitespace.
        let needle = name.lowercased()
        for raw in header.split(separator: ";") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == needle else { continue }
            var value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return decodeHeaderValue(String(value))
        }
        return nil
    }

    static func decodeQuotedPrintable(_ data: Data) -> Data {
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            if byte == 0x3D { // '='
                if i + 2 < data.endIndex,
                   let high = hex(data[i + 1]),
                   let low  = hex(data[i + 2]) {
                    out.append(UInt8(high * 16 + low))
                    i += 3
                    continue
                }
                // Soft line break: '=' followed by CRLF or LF.
                if i + 1 < data.endIndex,
                   data[i + 1] == 0x0D || data[i + 1] == 0x0A {
                    i += 1
                    while i < data.endIndex, data[i] == 0x0D || data[i] == 0x0A { i += 1 }
                    continue
                }
            }
            out.append(byte)
            i += 1
        }
        return Data(out)
    }

    private static func hex(_ b: UInt8) -> Int? {
        switch b {
        case 0x30...0x39: return Int(b - 0x30)        // '0'-'9'
        case 0x41...0x46: return Int(b - 0x41 + 10)   // 'A'-'F'
        case 0x61...0x66: return Int(b - 0x61 + 10)   // 'a'-'f'
        default: return nil
        }
    }

    static func stripHTML(_ html: String) -> String {
        let withBreaks = html
            .replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Byte sequences cached.
    private static let crlfcrlf: Data = Data("\r\n\r\n".utf8)
    private static let lflf:     Data = Data("\n\n".utf8)
}
