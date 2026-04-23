import Foundation

actor MailSyncService {
    private let repository: any MailRepository
    private let accountService: MailAccountService

    init(
        repository: any MailRepository,
        accountService: MailAccountService
    ) {
        self.repository = repository
        self.accountService = accountService
    }

    func bootstrap() async {
        MailClientLogger.sync.info("Bootstrapping MailStrea services")
    }

    func loadAccounts() async -> [MailAccount] {
        await accountService.loadAccounts()
    }

    func connectAccount(_ draft: MailAccountConnectionDraft) async throws -> MailAccount {
        try await accountService.connectAccount(draft)
    }

    func removeAccount(id: UUID) async throws {
        try await accountService.removeAccount(id: id)
    }

    func isProviderAvailable(_ providerType: MailProviderType) async -> Bool {
        await accountService.isProviderAvailable(providerType)
    }

    func availableProviderTypes() async -> [MailProviderType] {
        await accountService.availableProviderTypes()
    }

    @discardableResult
    func refreshAll() async throws -> Int {
        let accounts = await accountService.loadAccounts().filter(\.isEnabled)
        guard accounts.isEmpty == false else {
            throw MailServiceError.accountNotConfigured
        }

        var inboxMessages: [MailMessage] = []
        var firstError: Error?

        for account in accounts {
            do {
                let credentials = try await accountService.credentials(for: account)
                let provider = try await accountService.provider(for: account)
                let accountMessages = try await provider.fetchInbox(account: account, credentials: credentials, limit: 12)
                inboxMessages.append(contentsOf: accountMessages)
                await accountService.markSyncSuccess(for: account.id)
            } catch {
                if firstError == nil {
                    firstError = error
                }
                await accountService.markSyncFailure(for: account.id, message: error.localizedDescription)
            }
        }

        if inboxMessages.isEmpty, let firstError {
            throw firstError
        }

        let existingMessages = await repository.loadMessages()
        let localMessages = existingMessages.filter { $0.sidebarItem != .allMail }
        let sortedMessages = inboxMessages.sorted { $0.timestampLabel > $1.timestampLabel }
        await repository.saveMessages(sortedMessages + localMessages)
        return inboxMessages.count
    }

    func send(_ message: OutgoingMailMessage, preferredAccountID: UUID?) async throws -> MailMessage {
        let accounts = await accountService.loadAccounts()
        let selectedAccount = accounts.first(where: { $0.id == preferredAccountID && $0.isEnabled })
            ?? accounts.first(where: { $0.isEnabled })

        guard let account = selectedAccount else {
            throw MailServiceError.accountNotConfigured
        }

        let credentials = try await accountService.credentials(for: account)
        let provider = try await accountService.provider(for: account)
        try await provider.send(message: message, account: account, credentials: credentials)

        let sentMessage = makeLocalSentMessage(message, account: account)
        await repository.appendMessage(sentMessage)
        return sentMessage
    }

    private func makeLocalSentMessage(_ message: OutgoingMailMessage, account: MailAccount) -> MailMessage {
        let trimmedBody = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = trimmedBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let previewSource = paragraphs.first ?? trimmedBody
        let preview = previewSource.replacingOccurrences(of: "\n", with: " ").prefix(120)
        let now = Date()
        let shortTimeFormatter = DateFormatter()
        shortTimeFormatter.dateFormat = "HH:mm"

        let longTimeFormatter = DateFormatter()
        longTimeFormatter.locale = Locale.current
        longTimeFormatter.dateStyle = .medium
        longTimeFormatter.timeStyle = .short

        return MailMessage(
            accountID: account.id,
            sidebarItem: .sent,
            inboxFilter: .inbox,
            senderName: account.displayName,
            senderRole: account.emailAddress,
            recipientLine: "to \(message.to.joined(separator: ", "))",
            tag: account.providerType.shortTag,
            subject: message.subject.isEmpty ? "(No Subject)" : message.subject,
            preview: String(preview),
            timestampLabel: shortTimeFormatter.string(from: now),
            relativeTimestamp: longTimeFormatter.string(from: now),
            isPriority: false,
            bodyParagraphs: paragraphs.isEmpty ? [trimmedBody] : paragraphs,
            highlights: [],
            closing: ""
        )
    }
}
