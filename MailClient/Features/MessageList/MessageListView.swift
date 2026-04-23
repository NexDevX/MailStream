import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedMessageID) {
            ForEach(appState.filteredMessages) { message in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(message.senderName)
                            .font(.headline)
                        Spacer()
                        Text(message.receivedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(message.subject)
                        .font(.subheadline)
                        .fontWeight(message.isRead ? .regular : .semibold)

                    Text(message.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .tag(message.id)
            }
        }
        .navigationTitle(appState.selectedMailbox.rawValue)
        .searchable(text: $appState.searchText, prompt: "Search mail")
        .overlay {
            if appState.filteredMessages.isEmpty {
                EmptyStateView(
                    title: "No Messages",
                    systemImage: "tray",
                    message: "This mailbox is empty for the current search scope."
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isShowingCompose = true
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MessageListView()
            .environmentObject(AppState())
    }
}
