import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Unified Inbox")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)

            Divider()

            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(appState.filteredMessages) { message in
                        MessageCardView(
                            message: message,
                            isSelected: appState.selectedMessageID == message.id
                        )
                        .onTapGesture {
                            appState.selectMessage(message)
                        }
                    }
                }
                .padding(20)
            }
            .overlay {
                if appState.filteredMessages.isEmpty {
                    EmptyStateView(
                        title: "No messages here",
                        systemImage: "tray",
                        message: "Try another folder or clear the current search."
                    )
                }
            }
        }
        .background(AppTheme.canvas)
        .searchable(text: $appState.searchText, prompt: "Search mail")
    }
}

private struct MessageCardView: View {
    let message: MailMessage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(message.tag)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.05))
                    )

                Text(message.senderName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text(message.timestampLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Text(message.subject)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            Text(message.preview)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
                .lineLimit(3)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? AppTheme.selectedCard : AppTheme.panel.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.black.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0), radius: 18, x: 0, y: 8)
    }
}
