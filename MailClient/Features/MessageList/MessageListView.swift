import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Unified Inbox")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                LazyVStack(spacing: 12) {
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
                .padding(14)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(message.tag)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.05))
                    )

                Text(message.senderName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text(message.timestampLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Text(message.subject)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            Text(message.preview)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AppTheme.selectedCard : AppTheme.panel.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.black.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0), radius: 12, x: 0, y: 6)
    }
}
