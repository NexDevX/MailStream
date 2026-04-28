import Foundation
import Testing
@testable import MailStrea

@Suite("IMAPResponseParser")
struct IMAPResponseParserTests {

    // MARK: - Tagged completion

    @Test
    func parsesTaggedCompletion() {
        let ok = IMAPResponseParser.parseCompletion("A0001 OK LOGIN completed")
        #expect(ok?.tag == "A0001")
        #expect(ok?.status == .ok)
        #expect(ok?.text == "LOGIN completed")

        let no = IMAPResponseParser.parseCompletion("A0002 NO mailbox not selectable")
        #expect(no?.status == .no)

        let bad = IMAPResponseParser.parseCompletion("A0003 BAD command unknown")
        #expect(bad?.status == .bad)
    }

    @Test
    func returnsNilForMalformedCompletion() {
        #expect(IMAPResponseParser.parseCompletion("") == nil)
        #expect(IMAPResponseParser.parseCompletion("A0001") == nil)
    }

    // MARK: - Mailbox name (IMAP-UTF7) decoding

    @Test
    func decodesAsciiMailboxNameUnchanged() {
        #expect(IMAPResponseParser.decodeMailboxName("INBOX") == "INBOX")
        #expect(IMAPResponseParser.decodeMailboxName("Sent Messages") == "Sent Messages")
        #expect(IMAPResponseParser.decodeMailboxName("") == "")
    }

    @Test
    func decodesAmpersandEscape() {
        // `&-` is the literal `&` per RFC 3501.
        #expect(IMAPResponseParser.decodeMailboxName("AT&-T") == "AT&T")
        #expect(IMAPResponseParser.decodeMailboxName("&-") == "&")
    }

    @Test
    func decodesChineseFolderName() {
        // RFC 3501 example variants. "已发送" = U+5DF2 U+53D1 U+9001
        // UTF-16BE bytes = 5D F2 53 D1 90 01 → base64 = XfJT0ZAB
        #expect(IMAPResponseParser.decodeMailboxName("&XfJT0ZAB-") == "已发送")
        // QQ-served custom folder seen in the live smoke run.
        #expect(IMAPResponseParser.decodeMailboxName("&UXZO1mWHTvZZOQ-") == "其他文件夹")
    }

    @Test
    func decodesMixedAsciiAndEncoded() {
        // Sub-folders use the delimiter as a literal — encoded segments
        // sit between ASCII separators.
        let raw = "&UXZO1mWHTvZZOQ-/QQ&kK5O9ouilgU-"
        let decoded = IMAPResponseParser.decodeMailboxName(raw)
        #expect(decoded.contains("/QQ"))
        #expect(decoded.hasPrefix("其他文件夹"))
    }

    @Test
    func decoderToleratesMalformedPayload() {
        // No terminating `-` — emit the raw run, don't crash.
        let result = IMAPResponseParser.decodeMailboxName("&UXZO1m")
        #expect(result == "&UXZO1m")
    }

    // MARK: - LIST

    @Test
    func parsesListWithAttributes() {
        let item = IMAPResponseParser.parseList(#"* LIST (\HasNoChildren \Sent) "/" "Sent Messages""#)
        #expect(item?.attributes == ["\\HasNoChildren", "\\Sent"])
        #expect(item?.delimiter == "/")
        #expect(item?.name == "Sent Messages")
    }

    @Test
    func parsesListWithUnquotedName() {
        let item = IMAPResponseParser.parseList(#"* LIST (\HasNoChildren) "/" INBOX"#)
        #expect(item?.name == "INBOX")
    }

    @Test
    func parsesListWithNilDelimiter() {
        let item = IMAPResponseParser.parseList(#"* LIST () NIL "Shared Folders""#)
        #expect(item?.delimiter == nil)
        #expect(item?.name == "Shared Folders")
    }

    // MARK: - Folder role mapping

    @Test
    func mapsSpecialUseAttributesToRoles() {
        #expect(IMAPResponseParser.roleForAttributes(["\\Sent"], name: "Sent") == .sent)
        #expect(IMAPResponseParser.roleForAttributes(["\\Drafts"], name: "Drafts") == .drafts)
        #expect(IMAPResponseParser.roleForAttributes(["\\Junk"], name: "Spam") == .junk)
    }

    @Test
    func mapsLocalizedQQFolderNamesToRoles() {
        #expect(IMAPResponseParser.roleForAttributes([], name: "INBOX") == .inbox)
        #expect(IMAPResponseParser.roleForAttributes([], name: "已发送") == .sent)
        #expect(IMAPResponseParser.roleForAttributes([], name: "草稿箱") == .drafts)
        #expect(IMAPResponseParser.roleForAttributes([], name: "已删除") == .trash)
        #expect(IMAPResponseParser.roleForAttributes([], name: "垃圾邮件") == .junk)
    }

    // MARK: - SELECT

    @Test
    func parsesSelectCounts() {
        let summary = IMAPResponseParser.parseSelect(lines: [
            "* 18 EXISTS",
            "* 2 RECENT",
            "* OK [UIDVALIDITY 3857529045] UIDs valid",
            "* OK [UIDNEXT 4392] Predicted next UID"
        ])
        #expect(summary.exists == 18)
        #expect(summary.recent == 2)
        #expect(summary.uidValidity == 3857529045)
        #expect(summary.uidNext == 4392)
    }

    // MARK: - FETCH atom parsing

    @Test
    func parsesFetchHeaderAtoms() {
        // Body string is what would remain *after* the IMAP client
        // substitutes literals with `\u{1}<index>\u{1}` placeholders.
        let body = #"UID 12345 FLAGS (\Seen \Flagged) INTERNALDATE "01-Jan-2026 12:00:00 +0000" RFC822.SIZE 4096 BODY[HEADER] \#u{1}0\#u{1}"#
        let literal = Data("Subject: Test\r\nFrom: a@b.c\r\n\r\n".utf8)
        let item = IMAPResponseParser.parseFetchAtoms(
            sequenceNumber: 1,
            body: body,
            literals: [literal]
        )
        #expect(item.uid == 12345)
        #expect(item.flags.contains("\\Seen"))
        #expect(item.flags.contains("\\Flagged"))
        #expect(item.sizeBytes == 4096)
        #expect(item.headerLiteral == literal)
        #expect(item.internalDate != nil)
    }

    @Test
    func parsesFetchBodyLiteral() {
        let body = "UID 7 BODY[] \u{1}0\u{1}"
        let literal = Data("full RFC822".utf8)
        let item = IMAPResponseParser.parseFetchAtoms(
            sequenceNumber: 1,
            body: body,
            literals: [literal]
        )
        #expect(item.uid == 7)
        #expect(item.bodyLiteral == literal)
    }

    @Test
    func skipsUnknownAtomsWithoutLooping() {
        // `MODSEQ` and `X-GM-THRID` are common atoms we don't model.
        // The parser should consume one value each and proceed.
        let body = "UID 1 MODSEQ (12345) X-GM-THRID 999 FLAGS (\\Seen)"
        let item = IMAPResponseParser.parseFetchAtoms(sequenceNumber: 1, body: body, literals: [])
        #expect(item.uid == 1)
        #expect(item.flags == ["\\Seen"])
    }
}
