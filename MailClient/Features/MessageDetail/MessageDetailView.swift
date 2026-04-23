import SwiftUI

struct MessageDetailView: View {
    @EnvironmentObject private var appState: AppState
    let message: MailMessage?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(AppTheme.panel)
    }

    private var header: some View {
        HStack(spacing: 14) {
            CircleActionButton(systemImage: "arrowshape.turn.up.left")
            CircleActionButton(systemImage: "trash")

            Rectangle()
                .fill(AppTheme.panelBorder)
                .frame(width: 1, height: 26)

            Image(systemName: "tag.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Text(appState.selectionPositionText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(message.subject)
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(2)
                        .padding(.top, 22)

                    HStack(alignment: .center, spacing: 14) {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(message.senderInitials)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.senderName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(message.recipientLine)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Text(message.relativeTimestamp)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(message.bodyParagraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineSpacing(6)
                        }
                    }

                    if message.highlights.isEmpty == false {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(appState.strings.keyDecisions)
                                .font(.system(size: 21, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.textPrimary)

                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(message.highlights, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("•")
                                        Text(item)
                                            .lineSpacing(4)
                                    }
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                        }
                        .padding(22)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.canvas)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.panelBorder, lineWidth: 1)
                        )
                    }

                    Text(message.closing)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(6)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 42)
            }
        } else {
            EmptyStateView(
                title: appState.strings.selectMessageTitle,
                systemImage: "envelope.open",
                message: appState.strings.selectMessageMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CircleActionButton: View {
    let systemImage: String

    var body: some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    Circle()
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
