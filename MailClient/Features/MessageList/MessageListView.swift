import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var messageSelectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appState.strings.unifiedInbox)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Button {} label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppTheme.panelMuted.opacity(0.7))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(appState.filteredMessages) { message in
                        MessageCardView(
                            message: message,
                            isSelected: appState.selectedMessageID == message.id,
                            namespace: messageSelectionNamespace
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                appState.selectMessage(message)
                            }
                        }
                    }
                }
                .padding(12)
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
        .background(AppTheme.panel)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: appState.selectedMessageID)
    }
}

private struct MessageCardView: View {
    let message: MailMessage
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(message.isPriority ? AppTheme.priorityAccent : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(message.senderName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(message.senderRole)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(message.timestampLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Text(message.subject)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text(message.preview)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(message.tag)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(message.isPriority ? AppTheme.priorityAccent : AppTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(message.isPriority ? AppTheme.priorityAccent.opacity(0.10) : AppTheme.panelMuted.opacity(0.8))
                        )

                    if message.isPriority {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.priorityAccent)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.selectedCard)
                    .matchedGeometryEffect(id: "messageSelection", in: namespace)
                    .shadow(color: Color.black.opacity(0.07), radius: 16, x: 0, y: 6)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.panelElevated.opacity(0.52))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? AppTheme.focusAccent.opacity(0.22) : AppTheme.panelBorder.opacity(0.45), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
