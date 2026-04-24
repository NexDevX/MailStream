import SwiftUI

struct MessageDetailView: View {
    @EnvironmentObject private var appState: AppState
    let message: MailMessage?
    let layout: AppTheme.LayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            ReadingToolbar(message: message)
            Divider().overlay(DS.Color.line)
            content
        }
        .background(DS.Color.surface)
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    metaRow(for: message)
                        .padding(.top, 26)

                    Text(message.subject)
                        .font(DS.Font.serif(23, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                        .frame(maxWidth: 680, alignment: .leading)

                    senderBlock(for: message)
                        .padding(.bottom, 22)
                    Divider().overlay(DS.Color.line)
                        .padding(.bottom, 22)

                    AISummaryCard(
                        title: appState.strings.keyDecisionsTitle,
                        highlights: message.highlights
                    )
                    .padding(.bottom, 22)

                    bodyView(for: message)

                    attachments
                        .padding(.top, 24)

                    QuickReplyBox(replyTo: message.senderName, hint: appState.strings.replyTo)
                        .padding(.top, 26)
                        .padding(.bottom, 32)
                }
                .frame(maxWidth: layout.detailContentWidth, alignment: .leading)
                .padding(.horizontal, layout.detailHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(message.id)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: message.id)
        } else {
            EmptyStateView(
                title: appState.strings.selectMessageTitle,
                systemImage: "envelope.open",
                message: appState.strings.selectMessageMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: – Meta row (account badge · time · thread · priority)

    @ViewBuilder
    private func metaRow(for message: MailMessage) -> some View {
        HStack(spacing: 8) {
            let tint = providerTint(for: message)
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(accountLabel(for: message))
                    .font(DS.Font.sans(11, weight: .semibold))
                    .foregroundStyle(DS.Color.ink2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous).fill(tint.opacity(0.10))
            )

            dotSeparator
            Text(message.relativeTimestamp)
                .font(DS.Font.sans(11))
                .foregroundStyle(DS.Color.ink3)

            dotSeparator
            HStack(spacing: 4) {
                DSIcon(name: .layers, size: 10)
                Text("1 \(appState.strings.messagesUnit)")
            }
            .font(DS.Font.sans(11))
            .foregroundStyle(DS.Color.ink3)

            if message.isPriority {
                dotSeparator
                HStack(spacing: 3) {
                    DSIcon(name: .flame, size: 10)
                    Text(appState.strings.chipPriority)
                        .font(DS.Font.sans(11, weight: .semibold))
                }
                .foregroundStyle(DS.Color.amber)
            }
        }
    }

    private var dotSeparator: some View {
        Text("·").font(DS.Font.sans(11)).foregroundStyle(DS.Color.ink5)
    }

    // MARK: – Sender block

    @ViewBuilder
    private func senderBlock(for message: MailMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(
                initials: message.senderInitials,
                size: 34,
                tint: AvatarTint.neutral(for: message.senderName),
                providerColor: nil
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(message.senderName)
                        .font(DS.Font.sans(13, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                    if let email = senderEmail(for: message) {
                        Text("<\(email)>")
                            .font(DS.Font.mono(11))
                            .foregroundStyle(DS.Color.ink3)
                    }
                    verifiedBadge
                }
                Text(message.recipientLine)
                    .font(DS.Font.sans(11))
                    .foregroundStyle(DS.Color.ink3)
            }
            Spacer()
            LabelPill(text: "团队", tint: DS.Color.labelTeam)
        }
    }

    private var verifiedBadge: some View {
        HStack(spacing: 3) {
            DSIcon(name: .shield, size: 9)
            Text(appState.strings.verified)
        }
        .font(DS.Font.sans(10, weight: .semibold))
        .foregroundStyle(DS.Color.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(DS.Color.greenSoft)
        )
    }

    // MARK: – Body paragraphs

    @ViewBuilder
    private func bodyView(for message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(message.bodyParagraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(DS.Font.sans(13.5))
                    .foregroundStyle(DS.Color.ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message.closing)
                .font(DS.Font.sans(13.5))
                .foregroundStyle(DS.Color.ink2)
                .lineSpacing(5)
                .padding(.top, 4)
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    // MARK: – Attachments

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                DSIcon(name: .paperclip, size: 10)
                Text("2 个附件 · 共 1.4 MB")
            }
            .font(DS.Font.sans(10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(DS.Color.ink4)

            HStack(spacing: 8) {
                AttachmentCard(name: "design-tokens-v3.json", size: "12 KB", ext: "json", tint: DS.Color.greenSoft, tcolor: DS.Color.green)
                AttachmentCard(name: "before-after.pdf", size: "1.4 MB", ext: "pdf", tint: DS.Color.redSoft, tcolor: DS.Color.red)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
    }

    // MARK: – Helpers

    private func providerTint(for message: MailMessage) -> Color {
        if let id = message.accountID,
           let acc = appState.accounts.first(where: { $0.id == id }) {
            return ProviderPalette.color(for: acc.providerType)
        }
        return DS.Color.pGmail
    }

    private func accountLabel(for message: MailMessage) -> String {
        if let id = message.accountID,
           let acc = appState.accounts.first(where: { $0.id == id }) {
            return acc.displayName.isEmpty ? acc.emailAddress : acc.displayName
        }
        return "Gmail · 主"
    }

    private func senderEmail(for message: MailMessage) -> String? {
        message.senderRole.contains("@") ? message.senderRole : nil
    }
}

// MARK: - Reading toolbar

private struct ReadingToolbar: View {
    @EnvironmentObject private var appState: AppState
    let message: MailMessage?

    var body: some View {
        HStack(spacing: 2) {
            actionButton(icon: .reply, label: appState.strings.replyTo == "回复" ? "回复" : "Reply", kbd: "R", primary: true)
            actionButton(icon: .replyAll, label: nil, kbd: "⇧R")
            actionButton(icon: .forward, label: nil, kbd: "F")

            Rectangle().fill(DS.Color.line).frame(width: 1, height: 18).padding(.horizontal, 6)

            IconButton(icon: .archive)
            IconButton(icon: .trash)
            IconButton(icon: .tag)
            IconButton(icon: .clock)
            IconButton(icon: .pin)

            Spacer()

            Text(appState.selectionPositionText)
                .font(DS.Font.mono(11))
                .foregroundStyle(DS.Color.ink4)
            IconButton(icon: .chevronLeft)
            IconButton(icon: .chevronRight)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private func actionButton(icon: DSIconName, label: String?, kbd: String, primary: Bool = false) -> some View {
        Button {} label: {
            HStack(spacing: 6) {
                DSIcon(name: icon, size: 12)
                if let label {
                    Text(label).font(DS.Font.sans(11.5, weight: .medium))
                }
                Text(kbd).font(DS.Font.mono(10)).foregroundStyle(DS.Color.ink4)
            }
            .foregroundStyle(DS.Color.ink2)
            .padding(.horizontal, label == nil ? 8 : 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(primary ? DS.Color.surface2 : DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI summary card

private struct AISummaryCard: View {
    let title: String
    let highlights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DSIcon(name: .sparkle, size: 10)
                Text(title)
                    .font(DS.Font.sans(10.5, weight: .bold))
                    .tracking(0.6)
                Spacer()
                Text("Haiku · 0.4s")
                    .font(DS.Font.sans(9, weight: .medium))
                    .foregroundStyle(DS.Color.ink4)
                    .textCase(nil)
            }
            .textCase(.uppercase)
            .foregroundStyle(DS.Color.accentInk)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(highlights, id: \.self) { line in
                    Text("· \(line)")
                        .font(DS.Font.sans(12.5))
                        .foregroundStyle(DS.Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.accent.opacity(0.15), lineWidth: DS.Stroke.hairline)
        )
    }
}

// MARK: - Attachment card

private struct AttachmentCard: View {
    let name: String
    let size: String
    let ext: String
    let tint: Color
    let tcolor: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(tint)
                    .frame(width: 28, height: 28)
                Text(ext.uppercased())
                    .font(DS.Font.mono(9, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(tcolor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(DS.Font.sans(11.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Text(size)
                    .font(DS.Font.mono(10))
                    .foregroundStyle(DS.Color.ink4)
            }
            Spacer(minLength: 10)
            IconButton(icon: .download, size: 12)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
        )
    }
}

// MARK: - Quick reply

private struct QuickReplyBox: View {
    let replyTo: String
    let hint: String

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                DSIcon(name: .reply, size: 11)
                Text("\(hint) ").font(DS.Font.sans(11))
                    + Text(replyTo).font(DS.Font.sans(11, weight: .semibold))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(["Thanks!", "👍 看过了", "稍后细看"], id: \.self) { t in
                        Text(t)
                            .font(DS.Font.sans(10.5))
                            .foregroundStyle(DS.Color.ink2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Color.surface3))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(DS.Color.ink3)
            .background(DS.Color.surface2)
            Divider().overlay(DS.Color.line)

            TextEditor(text: $draft)
                .font(DS.Font.sans(12.5))
                .foregroundStyle(DS.Color.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(minHeight: 58)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("写点什么…")
                            .font(DS.Font.sans(12.5))
                            .foregroundStyle(DS.Color.ink4)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

            Divider().overlay(DS.Color.line)
            HStack(spacing: 4) {
                IconButton(icon: .bold)
                IconButton(icon: .italic)
                IconButton(icon: .link)
                IconButton(icon: .list)
                IconButton(icon: .paperclip)
                Spacer()
                Kbd(text: "⌘")
                Kbd(text: "↵")
                Button {} label: {
                    HStack(spacing: 5) {
                        DSIcon(name: .send, size: 11)
                        Text("发送").font(DS.Font.sans(11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Color.accent)
                    )
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DS.Color.surface2)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
        )
    }
}
