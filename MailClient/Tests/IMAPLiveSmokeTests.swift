import Foundation
import Testing
@testable import MailStrea

/// Path to the local credentials file. Lives at module scope so the
/// `@Suite` macro can reference it without triggering a circular
/// resolution through the suite type's own statics.
fileprivate func liveSmokeCredsPath() -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()    // Tests/
        .deletingLastPathComponent()    // MailClient/
        .deletingLastPathComponent()    // <repo root>/
        .appendingPathComponent("docs/password.TXT")
        .path
}

/// Live IMAP smoke test against a real QQ Mail account.
///
/// Gated on the presence of `docs/password.TXT` (gitignored). When
/// the file is absent — including all CI runs — the suite is skipped
/// with a soft message and no network call happens.
///
/// Credentials file format:
///
///     line 1 — full email address
///     line 2 — IMAP authorization code / app password
///
/// We never log credentials. Server data echoed in test output is
/// truncated to bounded snippets (subject prefix, first body line) so
/// long messages don't flood the console.
@Suite(
    "IMAPLiveSmokeTests",
    .disabled(if: !FileManager.default.fileExists(atPath: liveSmokeCredsPath()),
              "docs/password.TXT not present — live smoke disabled.")
)
struct IMAPLiveSmokeTests {

    @Test
    func qqMailRoundTrip() async throws {
        let creds = try Self.loadCredentials()
        let adapter = QQMailAdapter()

        let account = MailAccount(
            providerType: .qq,
            displayName: creds.email,
            emailAddress: creds.email
        )
        let credentials = MailAccountCredentials(
            accountID: account.id,
            emailAddress: creds.email,
            secret: creds.secret
        )

        // 1) LOGIN round-trip
        try await adapter.validateConnection(account: account, credentials: credentials)
        print("[smoke] validateConnection OK")

        // 2) Folder enumeration
        let folders = try await adapter.listFolders(account: account, credentials: credentials)
        #expect(folders.isEmpty == false, "QQ Mail returned no folders")
        print("[smoke] listFolders → \(folders.count) folders")
        for folder in folders.prefix(20) {
            let role = folder.role.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            print("  · role=\(role) remoteID=\(folder.remoteID) name=\(folder.name)")
        }

        guard let inbox = folders.first(where: { $0.role == .inbox })
            ?? folders.first(where: { $0.remoteID.uppercased() == "INBOX" }) else {
            Issue.record("Inbox folder not found in QQ Mail folder list")
            return
        }

        // 3) Header fetch (latest 5)
        let cursor = SyncCursor(lastUID: 0, uidValidity: nil, highestModseq: nil, lastFullSync: nil)
        let result = try await adapter.fetchHeaders(
            account: account,
            credentials: credentials,
            folder: inbox,
            cursor: cursor,
            limit: 5
        )
        #expect(result.headers.isEmpty == false, "Inbox came back empty")
        print("[smoke] fetchHeaders → \(result.headers.count) headers, " +
              "uidValidity=\(result.newCursor.uidValidity ?? 0)")
        for header in result.headers {
            let subjectSnippet = header.subject.prefix(60)
            print("  · UID=\(header.remoteUID) " +
                  "from=\(header.fromAddress) subj=\(subjectSnippet)")
        }

        // 4) Body fetch (latest only)
        let latest = try #require(result.headers.first)
        let body = try await adapter.fetchBody(
            account: account,
            credentials: credentials,
            folder: inbox,
            remoteUID: latest.remoteUID
        )
        let textLen = body.text?.count ?? 0
        let htmlLen = body.html?.count ?? 0
        print("[smoke] fetchBody UID=\(latest.remoteUID) → text=\(textLen)B html=\(htmlLen)B")
        #expect(textLen > 0 || htmlLen > 0, "Both text and html bodies are empty")

        // Surface a small sample so we can eyeball encoding correctness.
        if let text = body.text, text.isEmpty == false {
            let firstLine = text
                .components(separatedBy: .newlines)
                .first(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty == false })
                ?? ""
            print("  text snippet: \(firstLine.prefix(120))")
        }
        if let html = body.html {
            print("  html starts: \(html.prefix(120))")
        }
    }

    // MARK: - Credentials loading

    private struct LiveCredentials {
        let email: String
        let secret: String
    }

    private static func loadCredentials() throws -> LiveCredentials {
        let path = liveSmokeCredsPath()
        let url = URL(fileURLWithPath: path)
        let raw = try String(contentsOf: url, encoding: .utf8)
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard lines.count >= 2 else {
            throw NSError(
                domain: "IMAPLiveSmoke",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Credentials file at \(path) must have ≥ 2 non-empty lines (email, secret)."]
            )
        }
        return LiveCredentials(email: lines[0], secret: lines[1])
    }

}
