import Foundation

enum InboxFilterChip: String, CaseIterable, Identifiable {
    case all, unread, priority, attach, mentions
    var id: String { rawValue }
}

enum AppRoute: Hashable {
    case mail
    case onboarding
    case accountWizard
    case settings
    case search
    case compose
}

struct ComposeDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var to: String
    var cc: String
    var bcc: String
    var subject: String
    var body: String
    var fromAccountID: MailAccount.ID?
    var showCcBcc: Bool
    var lastSavedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        to: String = "",
        cc: String = "",
        bcc: String = "",
        subject: String = "",
        body: String = "",
        fromAccountID: MailAccount.ID? = nil,
        showCcBcc: Bool = false,
        lastSavedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.fromAccountID = fromAccountID
        self.showCcBcc = showCcBcc
        self.lastSavedAt = lastSavedAt
    }
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
    @Published var route: AppRoute = .mail
    @Published var pendingWizardProvider: MailProviderType = .gmail
    @Published var composeDrafts: [ComposeDraft] = []
    @Published var activeDraftID: ComposeDraft.ID?
    @Published var selectedFilterChip: InboxFilterChip = .all {
        didSet { syncSelectionIfNeeded() }
    }
    /// Optional account scope — if set, only mail from this account is shown.
    @Published var scopedAccountID: MailAccount.ID? {
        didSet { syncSelectionIfNeeded() }
    }
    /// Optional label scope (sidebar label rows). Stored by label key, not enum.
    @Published var scopedLabelKey: String? {
        didSet { syncSelectionIfNeeded() }
    }
    /// Snooze toast / placeholder dialog flag.
    @Published var snoozeBannerMessage: String?
    /// Disabled-account ids (we don't yet persist; UI-side mock).
    @Published var disabledAccountIDs: Set<MailAccount.ID> = []
    /// Set to true once the user dismisses Onboarding manually so RootView
    /// won't force them back when accounts is still empty.
    @Published var hasDismissedOnboarding: Bool = false
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
            .filter(matchesAccountScope)
            .filter(matchesLabelScope)
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

    // MARK: - Account UI helpers

    /// Mock toggle — flips local enabled-set without touching the credential
    /// store. Real impl would push the change down to MailSyncService.
    func toggleAccountEnabled(_ account: MailAccount) {
        if disabledAccountIDs.contains(account.id) {
            disabledAccountIDs.remove(account.id)
            mailboxStatusMessage = strings.accountConnected
        } else {
            disabledAccountIDs.insert(account.id)
            mailboxStatusMessage = "\(account.displayName.isEmpty ? account.emailAddress : account.displayName) — paused"
        }
    }

    func isAccountDisabled(_ account: MailAccount) -> Bool {
        disabledAccountIDs.contains(account.id)
    }

    /// Sidebar account row → scope inbox to that account.
    func scopeToAccount(_ accountID: MailAccount.ID?) {
        scopedAccountID = accountID
        scopedLabelKey = nil
        selectedSidebarItem = .allMail
        route = .mail
    }

    /// Sidebar label row → scope to label key (matches against message.tag).
    func scopeToLabel(_ key: String?) {
        scopedLabelKey = key
        route = .mail
    }

    func clearScopes() {
        scopedAccountID = nil
        scopedLabelKey = nil
    }

    // MARK: - Snooze (mock)

    /// Mock snooze — surfaces a transient banner. Real impl would write to
    /// the backing store and re-deliver at the chosen time.
    func snoozeSelectedMessage(label: String) {
        guard let msg = selectedMessage else { return }
        snoozeBannerMessage = "「\(msg.subject)」 已稍后提醒：\(label)"
    }

    // MARK: - Reply / Forward prefill

    func reply(to message: MailMessage, all: Bool = false) {
        let prefix = "Re: "
        let subject = message.subject.hasPrefix(prefix) ? message.subject : prefix + message.subject
        let recipient = message.senderName // mock — sender role not parsed as email
        let body = "\n\n— \n在 \(message.timestampLabel) \(message.senderName) 写道：\n> \(message.bodyParagraphs.first ?? message.preview)"
        let cc = all ? message.recipientLine : ""
        openCompose(prefill: ComposeDraft(
            to: recipient,
            cc: cc,
            subject: subject,
            body: body,
            fromAccountID: message.accountID ?? accounts.first?.id,
            showCcBcc: all
        ))
    }

    func forward(message: MailMessage) {
        let prefix = "Fwd: "
        let subject = message.subject.hasPrefix(prefix) ? message.subject : prefix + message.subject
        let body = "\n\n---------- 转发邮件 ----------\n发件人：\(message.senderName)\n时间：\(message.timestampLabel)\n主题：\(message.subject)\n\n\(message.bodyParagraphs.joined(separator: "\n\n"))"
        openCompose(prefill: ComposeDraft(
            subject: subject,
            body: body,
            fromAccountID: message.accountID ?? accounts.first?.id
        ))
    }

    // MARK: - Compose tabs

    func openCompose(prefill: ComposeDraft? = nil) {
        let draft = prefill ?? ComposeDraft(fromAccountID: selectedAccountID ?? accounts.first?.id)
        if composeDrafts.contains(where: { $0.id == draft.id }) == false {
            composeDrafts.append(draft)
        }
        activeDraftID = draft.id
        route = .compose
    }

    func closeCompose(_ id: ComposeDraft.ID) {
        composeDrafts.removeAll { $0.id == id }
        if activeDraftID == id {
            activeDraftID = composeDrafts.last?.id
        }
        if composeDrafts.isEmpty {
            route = .mail
        }
    }

    func updateDraft(_ id: ComposeDraft.ID, _ mutator: (inout ComposeDraft) -> Void) {
        guard let index = composeDrafts.firstIndex(where: { $0.id == id }) else { return }
        mutator(&composeDrafts[index])
        composeDrafts[index].lastSavedAt = Date()
    }

    func sendDraft(_ id: ComposeDraft.ID) async {
        guard let draft = composeDrafts.first(where: { $0.id == id }) else { return }
        do {
            try await sendMail(to: draft.to, subject: draft.subject, body: draft.body)
            closeCompose(id)
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

    private func matchesAccountScope(_ message: MailMessage) -> Bool {
        guard let scope = scopedAccountID else { return true }
        return message.accountID == scope
    }

    private func matchesLabelScope(_ message: MailMessage) -> Bool {
        guard let key = scopedLabelKey else { return true }
        // mock: match label key against tag (case-insensitive contains)
        return message.tag.lowercased().contains(key.lowercased())
            || message.preview.contains(key)
            || message.subject.contains(key)
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
