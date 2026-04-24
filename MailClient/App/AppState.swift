import Foundation

enum InboxFilterChip: String, CaseIterable, Identifiable {
    case all, unread, priority, attach, mentions
    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    private static let languageDefaultsKey = "mailclient.language"

    private let repository: any MailRepository
    private let syncService: MailSyncService

    @Published var selectedSidebarItem: SidebarItem = .allMail {
        didSet { syncSelectionIfNeeded() }
    }
    @Published var selectedInboxFilter: InboxFilter = .inbox {
        didSet { syncSelectionIfNeeded() }
    }
    @Published var selectedMessageID: MailMessage.ID?
    @Published var searchText = ""
    @Published var isShowingCompose = false
    @Published var isShowingCommandPalette = false
    @Published var selectedFilterChip: InboxFilterChip = .all {
        didSet { syncSelectionIfNeeded() }
    }
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageDefaultsKey)
        }
    }
    @Published var selectedAccountID: MailAccount.ID?
    @Published var isRefreshingMailbox = false
    @Published var mailboxStatusMessage: String?
    @Published private(set) var availableProviderTypes: [MailProviderType] = []
    @Published private(set) var accounts: [MailAccount] = []
    @Published private(set) var messages: [MailMessage]

    init(
        repository: any MailRepository,
        syncService: MailSyncService,
        initialMessages: [MailMessage]
    ) {
        self.repository = repository
        self.syncService = syncService
        self.messages = initialMessages
        self.language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? ""
        ) ?? .english
        self.selectedMessageID = initialMessages.first?.id
        syncSelectionIfNeeded()
    }

    var strings: AppStrings {
        AppStrings(language: language)
    }

    var filteredMessages: [MailMessage] {
        messages
            .filter(matchesSidebarItem)
            .filter(matchesInboxFilter)
            .filter(matchesFilterChip)
            .filter(matchesSearchText)
    }

    var allMessagesCount: Int { messages.filter { $0.sidebarItem == .allMail }.count }
    var unreadCount: Int { max(1, allMessagesCount / 3) } // UI-layer heuristic until unread is modelled

    func chipCount(_ chip: InboxFilterChip) -> Int {
        let base = messages.filter(matchesSidebarItem).filter(matchesInboxFilter)
        switch chip {
        case .all:       return base.count
        case .unread:    return max(0, base.count - (base.count / 2))
        case .priority:  return base.filter(\.isPriority).count
        case .attach:    return base.filter { $0.preview.contains("附件") || $0.preview.lowercased().contains("attach") }.count
        case .mentions:  return base.filter { $0.bodyParagraphs.joined().contains("@") }.count
        }
    }

    var selectedMessage: MailMessage? {
        filteredMessages.first { $0.id == selectedMessageID }
            ?? messages.first { $0.id == selectedMessageID }
    }

    var selectionPositionText: String {
        guard let selectedMessageID,
              let index = filteredMessages.firstIndex(where: { $0.id == selectedMessageID })
        else {
            return strings.selectionPosition(current: 0, total: filteredMessages.count)
        }

        return strings.selectionPosition(current: index + 1, total: filteredMessages.count)
    }

    var activeAccounts: [MailAccount] {
        accounts.filter(\.isEnabled)
    }

    func bootstrap() async {
        await syncService.bootstrap()
        await reloadProviderAvailability()
        await reloadAccounts()
        await reloadMessages()

        if activeAccounts.isEmpty == false {
            await refreshMailbox()
        }
    }

    func selectMessage(_ message: MailMessage) {
        selectedMessageID = message.id
    }

    func reloadMessages() async {
        messages = await repository.loadMessages()
        syncSelectionIfNeeded()
    }

    func reloadAccounts() async {
        accounts = await syncService.loadAccounts()
        if accounts.contains(where: { $0.id == selectedAccountID }) == false {
            selectedAccountID = accounts.first?.id
        }
    }

    func reloadProviderAvailability() async {
        availableProviderTypes = await syncService.availableProviderTypes()
    }

    func isProviderAvailable(_ providerType: MailProviderType) -> Bool {
        availableProviderTypes.contains(providerType)
    }

    func refreshMailbox() async {
        guard isRefreshingMailbox == false else {
            return
        }

        isRefreshingMailbox = true
        mailboxStatusMessage = strings.syncingMailbox
        defer { isRefreshingMailbox = false }

        do {
            let fetchedCount = try await syncService.refreshAll()
            await reloadAccounts()
            await reloadMessages()
            mailboxStatusMessage = strings.syncSucceeded(count: fetchedCount)
        } catch {
            await reloadAccounts()
            mailboxStatusMessage = error.localizedDescription
        }
    }

    func connectAccount(
        providerType: MailProviderType,
        displayName: String,
        emailAddress: String,
        secret: String
    ) async {
        do {
            let account = try await syncService.connectAccount(
                MailAccountConnectionDraft(
                    providerType: providerType,
                    displayName: displayName,
                    emailAddress: emailAddress,
                    secret: secret
                )
            )
            await reloadAccounts()
            selectedAccountID = account.id
            mailboxStatusMessage = strings.accountSaved
            await refreshMailbox()
        } catch {
            mailboxStatusMessage = error.localizedDescription
        }
    }

    func removeAccount(_ account: MailAccount) async {
        do {
            try await syncService.removeAccount(id: account.id)
            await reloadAccounts()
            mailboxStatusMessage = strings.accountRemoved
        } catch {
            mailboxStatusMessage = error.localizedDescription
        }
    }

    func sendMail(to recipientText: String, subject: String, body: String) async throws {
        let recipients = recipientText
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let outgoingMail = OutgoingMailMessage(
            to: recipients,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body
        )

        _ = try await syncService.send(outgoingMail, preferredAccountID: selectedAccountID)
        await reloadMessages()
        mailboxStatusMessage = strings.sendSucceeded
    }

    private func matchesSidebarItem(_ message: MailMessage) -> Bool {
        switch selectedSidebarItem {
        case .allMail:
            return message.sidebarItem == .allMail
        case .priority:
            return message.isPriority
        case .drafts:
            return message.sidebarItem == .drafts
        case .sent:
            return message.sidebarItem == .sent
        case .trash:
            return message.sidebarItem == .trash
        }
    }

    private func matchesInboxFilter(_ message: MailMessage) -> Bool {
        switch selectedInboxFilter {
        case .inbox:
            return message.inboxFilter == .inbox
        case .focused:
            return message.inboxFilter == .focused
        case .archive:
            return message.inboxFilter == .archive
        }
    }

    private func matchesFilterChip(_ message: MailMessage) -> Bool {
        switch selectedFilterChip {
        case .all:      return true
        case .unread:   return true // placeholder until unread is modelled
        case .priority: return message.isPriority
        case .attach:   return message.preview.lowercased().contains("attach") || message.preview.contains("附件")
        case .mentions: return message.bodyParagraphs.joined().contains("@")
        }
    }

    private func matchesSearchText(_ message: MailMessage) -> Bool {
        guard searchText.isEmpty == false else {
            return true
        }

        let query = searchText.lowercased()
        return message.subject.lowercased().contains(query)
            || message.preview.lowercased().contains(query)
            || message.senderName.lowercased().contains(query)
            || message.senderRole.lowercased().contains(query)
            || message.tag.lowercased().contains(query)
    }

    private func syncSelectionIfNeeded() {
        if filteredMessages.contains(where: { $0.id == selectedMessageID }) == false {
            selectedMessageID = filteredMessages.first?.id
        }
    }
}
