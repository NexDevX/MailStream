import Foundation

/// Defensive sanitizer for body paragraphs that may still carry raw MIME
/// noise (boundary lines, header continuation, encoded blocks). Used by the
/// reading pane until the IMAP/MIME parser is hardened.
///
/// Strategy:
/// - Drop lines that are MIME boundaries (`--xyz` or `----xyz`).
/// - Drop header-shaped lines (`Content-Type:`, `Content-Transfer-Encoding:`,
///   `MIME-Version:`, `boundary=…`) that often leak when only TEXT is fetched
///   from a multipart message without the parser walking subparts.
/// - Drop trailing/leading whitespace-only paragraphs.
/// - Collapse runs of more than one blank line.
/// - If a paragraph is *entirely* MIME goo, drop it.
///
/// We never modify content that looks like real text; the rule is
/// conservative — only drop lines that pattern-match known MIME shapes.
enum MailBodyCleaner {

    /// Header lines we drop when they appear inline with body text.
    private static let headerPrefixes: [String] = [
        "Content-Type:",
        "Content-Transfer-Encoding:",
        "Content-Disposition:",
        "Content-ID:",
        "Content-Description:",
        "MIME-Version:",
        "X-MIME-",
    ]

    static func clean(_ paragraphs: [String]) -> [String] {
        paragraphs
            .map(cleanParagraph)
            .filter { $0.isEmpty == false }
    }

    static func cleanParagraph(_ paragraph: String) -> String {
        var keptLines: [String] = []
        var skippingHeaderContinuation = false

        for rawLine in paragraph.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // MIME boundary: lines that start with -- and contain mimepart/boundary tokens
            if isMimeBoundary(trimmed) {
                skippingHeaderContinuation = false
                continue
            }

            // RFC822-style header (Name: value)
            if isMimeHeader(trimmed) {
                skippingHeaderContinuation = true
                continue
            }

            // Folded continuation lines start with whitespace; skip if we're inside a header.
            if skippingHeaderContinuation, line.first?.isWhitespace == true {
                continue
            }

            skippingHeaderContinuation = false
            keptLines.append(line)
        }

        let joined = keptLines.joined(separator: "\n")
        // Collapse 3+ consecutive blank lines into 2.
        return joined
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMimeBoundary(_ line: String) -> Bool {
        guard line.hasPrefix("--") else { return false }
        // Real boundaries always contain alphanumeric tokens, often `=`.
        // Be conservative: also accept the bare "--" closing boundary.
        return line.count <= 2
            || line.contains("mimepart")
            || line.contains("=_")
            || line.range(of: "^--[A-Za-z0-9_=]{6,}", options: .regularExpression) != nil
    }

    private static func isMimeHeader(_ line: String) -> Bool {
        for prefix in headerPrefixes {
            if line.hasPrefix(prefix) { return true }
        }
        // Generic catch: a header is `Name-Like: value` where Name has only
        // letters/digits/hyphen and value follows a colon+space. Limit to
        // <= 40 chars before the colon to avoid false positives on text
        // with colons mid-sentence ("Decision: ship it").
        if let colon = line.firstIndex(of: ":") {
            let head = line[..<colon]
            guard head.count <= 40 else { return false }
            let validChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
            // Must be all-header-chars and contain at least one hyphen or be CamelCase.
            if head.unicodeScalars.allSatisfy({ validChars.contains($0) }),
               head.contains("-"),
               line[line.index(after: colon)...].hasPrefix(" ") || line[line.index(after: colon)...].isEmpty {
                return true
            }
        }
        return false
    }
}
