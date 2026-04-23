import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appState.strings.unifiedInbox)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 9) {
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
                .padding(10)
            }
            .overlay {
                if appState.filteredMessages.isEmpty {
                    EmptyStateView(
                        title: appState.strings.noMessagesTitle,
                        systemImage: "tray",
                        message: appState.strings.noMessagesMessage
                    )
                }
            }
        }
        .background(AppTheme.canvas)
        .searchable(text: $appState.searchText, prompt: appState.strings.searchMail)
    }
}

private struct MessageCardView: View {
    let message: MailMessage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.tag)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.05))
                    )

                Text(message.senderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text(message.timestampLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Text(message.subject)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            Text(message.preview)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AppTheme.selectedCard : AppTheme.panel.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.black.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.045 : 0), radius: 8, x: 0, y: 4)
    }
}
