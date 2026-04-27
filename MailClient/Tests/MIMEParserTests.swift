import Foundation
import Testing
@testable import MailStrea

@Suite("MIMEParser")
struct MIMEParserTests {

    // MARK: - Plain text

    @Test
    func parsesSimpleTextBody() {
        let raw = """
        From: alice@example.com
        To: bob@example.com
        Subject: Hello
        Content-Type: text/plain; charset=utf-8

        Hi Bob,

        Just checking in.

        — Alice
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.headers["subject"] == "Hello")
        #expect(parsed.textBody.contains("Hi Bob,"))
        #expect(parsed.textBody.contains("Just checking in."))
        #expect(parsed.textBody.contains("Alice"))
        #expect(parsed.attachments.isEmpty)
    }

    @Test
    func bodyIsNotTruncatedAtFirstBlankLine() {
        // Regression test for the bug where header/body split fired on every
        // blank line, leaving only the first paragraph visible.
        let raw = """
        Subject: Long
        Content-Type: text/plain; charset=utf-8

        First paragraph.

        Second paragraph.

        Third paragraph.
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.textBody.contains("First paragraph."))
        #expect(parsed.textBody.contains("Second paragraph."))
        #expect(parsed.textBody.contains("Third paragraph."))
    }

    // MARK: - Multipart

    @Test
    func picksTextPlainFromMultipartAlternative() {
        let raw = """
        Subject: Hi
        Content-Type: multipart/alternative; boundary="abc"

        --abc
        Content-Type: text/plain; charset=utf-8

        plain version
        --abc
        Content-Type: text/html; charset=utf-8

        <p>html version</p>
        --abc--
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.textBody.contains("plain version"))
        #expect(parsed.textBody.contains("html version") == false)
        #expect(parsed.htmlBody?.contains("<p>html version</p>") == true)
    }

    @Test
    func fallsBackToHtmlWhenNoPlainPart() {
        let raw = """
        Subject: HTML only
        Content-Type: multipart/alternative; boundary="x"

        --x
        Content-Type: text/html; charset=utf-8

        <p>just html</p>
        --x--
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.textBody.contains("just html"))
    }

    @Test
    func collectsAttachmentsFromMixed() {
        let raw = """
        Subject: with file
        Content-Type: multipart/mixed; boundary="m"

        --m
        Content-Type: text/plain; charset=utf-8

        See attached.
        --m
        Content-Type: application/pdf; name="report.pdf"
        Content-Disposition: attachment; filename="report.pdf"
        Content-Transfer-Encoding: base64

        UmVwb3J0IGNvbnRlbnQ=
        --m--
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.textBody.contains("See attached."))
        #expect(parsed.attachments.count == 1)
        #expect(parsed.attachments.first?.filename == "report.pdf")
        #expect(parsed.attachments.first?.mimeType == "application/pdf")
    }

    // MARK: - Encodings

    @Test
    func decodesQuotedPrintable() {
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Hello =E4=BD=A0=E5=A5=BD=
         world
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.textBody.contains("Hello 你好"))
    }

    @Test
    func decodesBase64Body() {
        let body64 = Data("Hello base64!".utf8).base64EncodedString()
        let raw = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        \(body64)
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        #expect(parsed.textBody.contains("Hello base64!"))
    }

    @Test
    func decodesRfc2047EncodedSubject() {
        let payload = Data("你好世界".utf8).base64EncodedString()
        let raw = """
        Subject: =?UTF-8?B?\(payload)?=
        Content-Type: text/plain; charset=utf-8

        body
        """.replacingOccurrences(of: "\n", with: "\r\n")

        let parsed = MIMEParser.parse(Data(raw.utf8))
        let decodedSubject = MIMEParser.decodeHeaderValue(parsed.headers["subject"] ?? "")
        #expect(decodedSubject == "你好世界")
    }
}
