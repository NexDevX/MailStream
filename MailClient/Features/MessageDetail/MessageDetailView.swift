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
        HStack(spacing: 18) {
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(message.subject)
                        .font(.system(size: 44, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(2)
                        .padding(.top, 28)

                    HStack(alignment: .center, spacing: 18) {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Text(message.senderInitials)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.senderName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(message.recipientLine)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Text(message.relativeTimestamp)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(message.bodyParagraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineSpacing(8)
                        }
                    }

                    if message.highlights.isEmpty == false {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Key Decisions:")
                                .font(.system(size: 24, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.textPrimary)

                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(message.highlights, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("•")
                                        Text(item)
                                            .lineSpacing(6)
                                    }
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                        }
                        .padding(28)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.canvas)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.panelBorder, lineWidth: 1)
                        )
                    }

                    Text(message.closing)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(8)
                        .padding(.bottom, 44)
                }
                .padding(.horizontal, 58)
            }
        } else {
            EmptyStateView(
                title: "Select a message",
                systemImage: "envelope.open",
                message: "Pick an item from the list to open the reading surface."
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 42, height: 42)
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
