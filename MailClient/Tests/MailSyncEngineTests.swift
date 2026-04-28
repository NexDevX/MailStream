import Foundation
import Testing
@testable import MailStrea

@Suite("MailSyncEngine helpers")
struct MailSyncEngineTests {

    private let account = MailAccount(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        providerType: .qq,
        displayName: "Alice",
        emailAddress: "alice@example.com"
    )

    // MARK: - synthesizeMessageID

    @Test
    func messageIDIsStableAcrossInvocations() {
        let header = makeHeader(uid: 12345, subject: "Hello")
        let a = MailSyncEngine.synthesizeMessageID(for: header, accountID: account.id)
        let b = MailSyncEngine.synthesizeMessageID(for: header, accountID: account.id)
        #expect(a == b)
    }

    @Test
    func messageIDDiffersByUID() {
        let h1 = makeHeader(uid: 1, subject: "A")
        let h2 = makeHeader(uid: 2, subject: "A")
        let a = MailSyncEngine.synthesizeMessageID(for: h1, accountID: account.id)
        let b = MailSyncEngine.synthesizeMessageID(for: h2, accountID: account.id)
        #expect(a != b)
    }

    @Test
    func messageIDDiffersByAccount() {
        let header = makeHeader(uid: 1, subject: "A")
        let other = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let a = MailSyncEngine.synthesizeMessageID(for: header, accountID: account.id)
        let b = MailSyncEngine.synthesizeMessageID(for: header, accountID: other)
        #expect(a != b)
    }

    // MARK: - makeMailMessage

    @Test
    func mailMessageMapsCoreFields() {
        let header = RemoteHeader(
            remoteUID: 42,
            messageID: "<abc@example.com>",
            subject: "Quarterly review",
            fromName: "Bob",
            fromAddress: "bob@example.com",
            toAddresses: ["alice@example.com", "team@example.com"],
            sentAt: Date(timeIntervalSince1970: 1_700_000_000),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            flagsFlagged: true
        )
        let message = MailSyncEngine.makeMailMessage(from: header, account: account)
        #expect(message.subject == "Quarterly review")
        #expect(message.senderName == "Bob")
        #expect(message.senderRole == "bob@example.com")
        #expect(message.recipientLine.contains("alice@example.com"))
        #expect(message.recipientLine.contains("team@example.com"))
        #expect(message.tag == account.providerType.shortTag)
        #expect(message.isPriority == true)
        #expect(message.accountID == account.id)
    }

    @Test
    func mailMessageFallsBackToFromAddressForBlankName() {
        let header = makeHeader(uid: 1, subject: "x", fromName: "", fromAddress: "x@y.com")
        let message = MailSyncEngine.makeMailMessage(from: header, account: account)
        #expect(message.senderName == "x@y.com")
    }

    @Test
    func mailMessageFallsBackToAccountAddressWhenToIsEmpty() {
        let header = makeHeader(uid: 1, subject: "x")
        let message = MailSyncEngine.makeMailMessage(from: header, account: account)
        #expect(message.recipientLine == "to alice@example.com")
    }

    // MARK: - makeMailMessageBody

    @Test
    func bodyParagraphSplitNormalizesLineEndings() {
        let body = RemoteBody(text: "Line 1\r\n\r\nLine 2\r\n", html: nil)
        let local = MailSyncEngine.makeMailMessageBody(from: body)
        #expect(local.paragraphs == ["Line 1", "Line 2"])
    }

    @Test
    func bodyPreservesHTML() {
        let body = RemoteBody(text: "plain", html: "<p>rich</p>")
        let local = MailSyncEngine.makeMailMessageBody(from: body)
        #expect(local.htmlBody == "<p>rich</p>")
    }

    // MARK: - Helpers

    private func makeHeader(
        uid: Int64,
        subject: String,
        fromName: String = "Sender",
        fromAddress: String = "sender@example.com"
    ) -> RemoteHeader {
        RemoteHeader(
            remoteUID: uid,
            subject: subject,
            fromName: fromName,
            fromAddress: fromAddress,
            sentAt: Date(timeIntervalSince1970: 0),
            receivedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
