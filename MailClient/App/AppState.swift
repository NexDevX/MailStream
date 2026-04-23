import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var selectedMailbox: Mailbox = .inbox
    @Published var selectedMessageID: MailMessage.ID?
    @Published var searchText = ""
    @Published var isShowingCompose = false
    @Published var messages: [MailMessage]

    init(messages: [MailMessage] = MailMessage.samples) {
        self.messages = messages
        self.selectedMessageID = messages.first?.id
    }

    var filteredMessages: [MailMessage] {
        let mailboxScoped = messages.filter { $0.mailbox == selectedMailbox }
        guard searchText.isEmpty == false else {
            return mailboxScoped
        }

        return mailboxScoped.filter { message in
            message.subject.localizedCaseInsensitiveContains(searchText)
                || message.preview.localizedCaseInsensitiveContains(searchText)
                || message.senderName.localizedCaseInsensitiveContains(searchText)
                || message.senderEmail.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedMessage: MailMessage? {
        filteredMessages.first { $0.id == selectedMessageID }
            ?? messages.first { $0.id == selectedMessageID }
    }
}
