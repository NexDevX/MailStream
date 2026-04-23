import Foundation

@MainActor
final class AppState: ObservableObject {
    private let repository: any MailRepository

    @Published var selectedSidebarItem: SidebarItem = .allMail {
        didSet { syncSelectionIfNeeded() }
    }
    @Published var selectedInboxFilter: InboxFilter = .inbox {
        didSet { syncSelectionIfNeeded() }
    }
    @Published var selectedMessageID: MailMessage.ID?
    @Published var searchText = ""
    @Published var isShowingCompose = false
    @Published private(set) var messages: [MailMessage]

    init(repository: any MailRepository) {
        self.repository = repository
        let messages = repository.loadMessages()
        self.messages = messages
        self.selectedMessageID = messages.first?.id
        syncSelectionIfNeeded()
    }

    var filteredMessages: [MailMessage] {
        messages.filter(matchesSidebarItem).filter(matchesInboxFilter).filter(matchesSearchText)
    }

    var selectedMessage: MailMessage? {
        filteredMessages.first { $0.id == selectedMessageID }
            ?? messages.first { $0.id == selectedMessageID }
    }

    var selectionPositionText: String {
        guard let selectedMessageID,
              let index = filteredMessages.firstIndex(where: { $0.id == selectedMessageID })
        else {
            return "0 of \(filteredMessages.count)"
        }

        return "\(index + 1) of \(filteredMessages.count)"
    }

    func selectMessage(_ message: MailMessage) {
        selectedMessageID = message.id
    }

    func reloadMessages() {
        messages = repository.loadMessages()
        syncSelectionIfNeeded()
    }

    private func matchesSidebarItem(_ message: MailMessage) -> Bool {
        switch selectedSidebarItem {
        case .allMail:
            return true
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
