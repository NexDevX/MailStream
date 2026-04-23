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
        HStack(spacing: 10) {
            CircleActionButton(systemImage: "arrowshape.turn.up.left")
            CircleActionButton(systemImage: "trash")

            Rectangle()
                .fill(AppTheme.panelBorder)
                .frame(width: 1, height: 20)

            Image(systemName: "tag.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Text(appState.selectionPositionText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(message.subject)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(1)
                        .padding(.top, 16)

                    HStack(alignment: .center, spacing: 10) {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text(message.senderInitials)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.senderName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(message.recipientLine)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Text(message.relativeTimestamp)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(message.bodyParagraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: AppTheme.bodyFontSize, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineSpacing(4)
                        }
                    }

                    if message.highlights.isEmpty == false {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(appState.strings.keyDecisions)
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.textPrimary)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(message.highlights, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                        Text(item)
                                            .lineSpacing(3)
                                    }
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.canvas)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.panelBorder, lineWidth: 1)
                        )
                    }

                    Text(message.closing)
                        .font(.system(size: AppTheme.bodyFontSize, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(4)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 30)
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
                .frame(width: 30, height: 30)
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
