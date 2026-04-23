import SwiftUI

struct MessageDetailView: View {
    @EnvironmentObject private var appState: AppState
    let message: MailMessage?
    let layout: AppTheme.LayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(AppTheme.panelElevated)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ToolbarActionButton(systemImage: "arrowshape.turn.up.left")
            ToolbarActionButton(systemImage: "archivebox")
            ToolbarActionButton(systemImage: "trash", role: .destructive)

            Rectangle()
                .fill(AppTheme.panelBorder)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 4)

            ToolbarActionButton(systemImage: "tag")
            ToolbarActionButton(systemImage: "flag")

            Spacer()

            Text(appState.selectionPositionText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(AppTheme.panelElevated)
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(message.tag)
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(message.isPriority ? AppTheme.priorityAccent : AppTheme.focusAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill((message.isPriority ? AppTheme.priorityAccent : AppTheme.focusAccent).opacity(0.10))
                                )

                            if message.isPriority {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppTheme.priorityAccent)
                            }
                        }

                        Text(message.subject)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 26)

                    HStack(alignment: .center, spacing: 11) {
                        Circle()
                            .fill(AppTheme.panelMuted)
                            .frame(width: 38, height: 38)
                            .overlay {
                                Text(message.senderInitials)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(message.senderName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(message.senderRole)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }

                            Text(message.recipientLine)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Text(message.relativeTimestamp)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.bottom, 2)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(message.bodyParagraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if message.highlights.isEmpty == false {
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(AppTheme.focusAccent)
                                .frame(width: 3)

                            VStack(alignment: .leading, spacing: 12) {
                                Text(appState.strings.keyDecisions)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                ForEach(message.highlights, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 9) {
                                        Circle()
                                            .fill(AppTheme.focusAccent.opacity(0.74))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 6)

                                        Text(item)
                                            .lineSpacing(4)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                        }
                        .padding(15)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AppTheme.selectedCard.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(AppTheme.focusAccent.opacity(0.16), lineWidth: 1)
                        )
                    }

                    Text(message.closing)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(5)
                        .padding(.bottom, 34)
                }
                .id(message.id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .frame(maxWidth: layout.detailContentWidth, alignment: .leading)
                .padding(.horizontal, layout.detailHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: message.id)
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

private struct ToolbarActionButton: View {
    enum ButtonRole {
        case standard
        case destructive
    }

    let systemImage: String
    var role: ButtonRole = .standard

    var body: some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(role == .destructive ? AppTheme.destructive : AppTheme.textSecondary)
                .frame(width: 29, height: 29)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.panelMuted.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
