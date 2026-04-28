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
            // Reading-pane width policy:
            //  · header / footer text stays at `detailContentWidth` (680)
            //    for comfortable line-length when reading prose
            //  · body fills the entire detail pane width — HTML emails
            //    self-constrain via their own table widths and centering;
            //    plain-text bodies further self-cap at 680 internally
            let textWidth = layout.detailContentWidth
            let bodyWidth: CGFloat = .infinity

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Header column ────────────────────────────────────
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
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        senderBlock(for: message)
                            .padding(.bottom, 22)
                        Divider().overlay(DS.Color.line)
                            .padding(.bottom, 22)

                        if let highlights = appState.selectedBody?.highlights, highlights.isEmpty == false {
                            AISummaryCard(
                                title: appState.strings.keyDecisionsTitle,
                                highlights: highlights
                            )
                            .padding(.bottom, 22)
                        }
                    }
                    .frame(maxWidth: textWidth, alignment: .leading)

                    // ── Body (may be wider than the header) ──────────────
                    bodyView(for: message)
                        .frame(maxWidth: bodyWidth, alignment: .leading)

                    // ── Footer column (attachments + quick reply) ────────
                    VStack(alignment: .leading, spacing: 0) {
                        if message.attachments.isEmpty == false {
                            attachmentsView(for: message)
                                .padding(.top, 24)
                        }

                        QuickReplyBox(replyTo: message.senderName, hint: appState.strings.replyTo)
                            .padding(.top, 26)
                            .padding(.bottom, 32)
                    }
                    .frame(maxWidth: textWidth, alignment: .leading)
                }
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
                        .textSelection(.enabled)
                    if let email = senderEmail(for: message) {
                        Text("<\(email)>")
                            .font(DS.Font.mono(11))
                            .foregroundStyle(DS.Color.ink3)
                            .textSelection(.enabled)
                    }
                    verifiedBadge
                }
                Text(message.recipientLine)
                    .font(DS.Font.sans(11))
                    .foregroundStyle(DS.Color.ink3)
                    .textSelection(.enabled)
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
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .compositingGroup()
    }

    // MARK: – Body paragraphs
    //
    // The body lives in `appState.selectedBody`, lazy-loaded from the cache
    // when a message is selected. We render three states:
    //
    //  · loading   → shimmer placeholder (no jarring jump when bytes land)
    //  · empty     → fall back to the preview line (better than blank)
    //  · loaded    → cleaned paragraphs + closing
    //
    // `MailBodyCleaner` is still applied as a defensive last pass — most
    // bodies arrive clean from `MIMEParser`, but legacy data on disk may
    // still carry MIME residue.

    @ViewBuilder
    private func bodyView(for message: MailMessage) -> some View {
        let body = appState.selectedBody
        let isLoading = appState.isLoadingSelectedBody

        // We deliberately don't put `.animation(_, value: body)` here.
        // The body changes whenever the WebView reports a new height
        // (image load, font ready) — animating that would crossfade /
        // spring the entire pane on every height tick, which is the
        // "flashing while images load / list resizes" symptom. Instead
        // we let the per-message transition (driven by `.id(message.id)`
        // up in `content`) own the only fade animation.
        Group {
            if isLoading && body == nil {
                bodySkeleton
                    .frame(maxWidth: 680, alignment: .leading)
            } else if let html = body?.htmlBody, html.isEmpty == false {
                HTMLBodyContainer(messageID: message.id, html: html)
            } else {
                plainBodyView(message: message, body: body)
            }
        }
    }

    private func plainBodyView(message: MailMessage, body: MailMessageBody?) -> some View {
        let cleaned = MailBodyCleaner.clean(body?.paragraphs ?? [])
        return VStack(alignment: .leading, spacing: 14) {
            if cleaned.isEmpty {
                Text(message.preview.isEmpty ? "(空邮件)" : message.preview)
                    .font(DS.Font.sans(13.5))
                    .foregroundStyle(DS.Color.ink3)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                ForEach(cleaned, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(DS.Font.sans(13.5))
                        .foregroundStyle(DS.Color.ink)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let closing = body?.closing, closing.isEmpty == false {
                    Text(closing)
                        .font(DS.Font.sans(13.5))
                        .foregroundStyle(DS.Color.ink2)
                        .lineSpacing(5)
                        .padding(.top, 4)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    /// Three-line gray bar shimmer that matches body paragraph rhythm.
    /// Pure cosmetic — no Timer / repeatForever beyond DS.Motion.ambient.
    private var bodySkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([0.92, 0.78, 0.95, 0.65], id: \.self) { ratio in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DS.Color.surface3)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: CGFloat(ratio), y: 1, anchor: .leading)
                    .opacity(0.85)
            }
        }
    }

    // MARK: – Attachments

    private func attachmentsView(for message: MailMessage) -> some View {
        let totalBytes = message.attachments.reduce(0) { $0 + $1.sizeBytes }
        let summary = formatBytes(totalBytes)
        let zh = appState.language == .simplifiedChinese
        let title = zh
            ? "\(message.attachments.count) 个附件 · 共 \(summary)"
            : "\(message.attachments.count) attachment\(message.attachments.count == 1 ? "" : "s") · \(summary)"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                DSIcon(name: .paperclip, size: 10)
                Text(title)
            }
            .font(DS.Font.sans(10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(DS.Color.ink4)

            // Wrap so chips flow onto multiple lines for long attachment lists.
            FlowingHStack(spacing: 8) {
                ForEach(message.attachments) { attachment in
                    AttachmentCard(attachment: attachment) {
                        appState.snoozeBannerMessage = zh
                            ? "附件下载将在 IMAP 接入后支持（Phase 3）"
                            : "Attachment download will land with IMAP (Phase 3)"
                    }
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
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
            actionButton(icon: .reply, label: appState.strings.replyTo == "回复" ? "回复" : "Reply", kbd: "R", primary: true) {
                if let message { appState.reply(to: message) }
            }
            actionButton(icon: .replyAll, label: nil, kbd: "⇧R") {
                if let message { appState.reply(to: message, all: true) }
            }
            actionButton(icon: .forward, label: nil, kbd: "F") {
                if let message { appState.forward(message: message) }
            }

            Rectangle().fill(DS.Color.line).frame(width: 1, height: 18).padding(.horizontal, 6)

            IconButton(icon: .archive) {
                appState.mailboxStatusMessage = appState.language == .simplifiedChinese ? "已归档（mock）" : "Archived (mock)"
            }
            IconButton(icon: .trash) {
                appState.mailboxStatusMessage = appState.language == .simplifiedChinese ? "已移到废纸篓（mock）" : "Moved to trash (mock)"
            }
            IconButton(icon: .tag)
            // Snooze with menu
            Menu {
                Button("1 小时后") { appState.snoozeSelectedMessage(label: "1 小时后") }
                Button("今晚") { appState.snoozeSelectedMessage(label: "今晚") }
                Button("明天上午") { appState.snoozeSelectedMessage(label: "明天上午") }
                Button("下周一") { appState.snoozeSelectedMessage(label: "下周一") }
            } label: {
                DSIcon(name: .clock, size: 13)
                    .foregroundStyle(DS.Color.ink2)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            IconButton(icon: .pin) {
                appState.mailboxStatusMessage = appState.language == .simplifiedChinese ? "已置顶" : "Pinned"
            }

            Spacer()

            Text(appState.selectionPositionText)
                .font(DS.Font.mono(11))
                .foregroundStyle(DS.Color.ink4)
            IconButton(icon: .chevronLeft) { stepSelection(-1) }
            IconButton(icon: .chevronRight) { stepSelection(1) }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    /// Cycle through filteredMessages by `delta`.
    private func stepSelection(_ delta: Int) {
        let list = appState.filteredMessages
        guard list.isEmpty == false else { return }
        let currentIndex = list.firstIndex { $0.id == appState.selectedMessageID } ?? 0
        let next = (currentIndex + delta + list.count) % list.count
        appState.selectedMessageID = list[next].id
    }

    private func actionButton(icon: DSIconName, label: String?, kbd: String, primary: Bool = false, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
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
            .dsCard(cornerRadius: DS.Radius.sm, fill: primary ? DS.Color.surface2 : DS.Color.surface)
        }
        .buttonStyle(.plain)
        .hoverLift()
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
        .dsCard(
            cornerRadius: DS.Radius.md,
            fill: DS.Color.accentSoft,
            stroke: DS.Color.accent.opacity(0.15)
        )
    }
}

// MARK: - Attachment card

private struct AttachmentCard: View {
    let attachment: MailAttachment
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(palette.tint)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    Text(attachment.ext)
                        .font(DS.Font.mono(9, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(palette.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(DS.Font.sans(11.5, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(attachment.humanSize)
                        .font(DS.Font.mono(10))
                        .foregroundStyle(DS.Color.ink4)
                }
                Spacer(minLength: 8)
                DSIcon(name: .download, size: 11)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 220, maxWidth: 280)
            .dsCard(cornerRadius: DS.Radius.md)
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help(attachment.filename)
    }

    /// Color the badge by file family. Falls through to neutral for
    /// unknown / generic types.
    private var palette: (tint: Color, color: Color) {
        switch attachment.ext {
        case "PDF":
            return (DS.Color.redSoft, DS.Color.red)
        case "DOC", "DOCX", "RTF":
            return (DS.Color.accentSoft, DS.Color.accent)
        case "XLS", "XLSX", "CSV", "NUMBERS":
            return (DS.Color.greenSoft, DS.Color.green)
        case "PPT", "PPTX", "KEY":
            return (DS.Color.amberSoft, DS.Color.amber)
        case "JSON", "YAML", "YML", "TXT", "MD", "LOG":
            return (DS.Color.greenSoft, DS.Color.green)
        case "ZIP", "RAR", "7Z", "TAR", "GZ":
            return (DS.Color.amberSoft, DS.Color.amber)
        case "PNG", "JPG", "JPEG", "GIF", "HEIC", "WEBP":
            return (DS.Color.surface3, DS.Color.ink2)
        case "MP3", "WAV", "M4A":
            return (DS.Color.accentSoft, DS.Color.accentInk)
        case "MP4", "MOV", "MKV":
            return (DS.Color.surface3, DS.Color.ink2)
        default:
            return (DS.Color.surface3, DS.Color.ink2)
        }
    }
}

// MARK: - Quick reply

private struct QuickReplyBox: View {
    @EnvironmentObject private var appState: AppState
    let replyTo: String
    let hint: String

    @State private var draft: String = ""
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                DSIcon(name: .reply, size: 11)
                Text("\(hint) ").font(DS.Font.sans(11))
                    + Text(replyTo).font(DS.Font.sans(11, weight: .semibold))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(["Thanks!", "👍 看过了", "稍后细看"], id: \.self) { t in
                        Button {
                            draft = (draft.isEmpty ? "" : draft + "\n") + t
                        } label: {
                            Text(t)
                                .font(DS.Font.sans(10.5))
                                .foregroundStyle(DS.Color.ink2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DS.Color.surface3))
                                .clipShape(Capsule())
                                .compositingGroup()
                        }
                        .buttonStyle(.plain)
                        .hoverLift()
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
                Button {
                    Task { await sendQuickReply() }
                } label: {
                    HStack(spacing: 5) {
                        DSIcon(name: .send, size: 11)
                        Text(isSending ? "发送中…" : "发送").font(DS.Font.sans(11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Color.accent)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .compositingGroup()
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .keyboardShortcut(.return, modifiers: .command)
                .hoverLift()
                .padding(.leading, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DS.Color.surface2)
        }
        .dsCard(cornerRadius: DS.Radius.lg)
    }

    private func sendQuickReply() async {
        guard isSending == false else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty == false else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await appState.sendMail(to: replyTo, subject: "Re: ", body: body)
            draft = ""
        } catch {
            appState.mailboxStatusMessage = error.localizedDescription
        }
    }
}

// MARK: - HTML body container
//
// Owns the WKWebView lifecycle and the "show remote images" toggle. The
// container scopes its state to a `messageID` so navigating between
// messages resets the toggle and the measured height — the previous
// message's height never bleeds into the new one's first paint.

private struct HTMLBodyContainer: View {
    @EnvironmentObject private var appState: AppState
    /// Set to `true` while the user is dragging the list/detail pane
    /// resizer in `RootView`. While true we suppress the WKWebView
    /// height callback so `contentHeight` doesn't bounce up and down
    /// in lock-step with the HTML reflowing at every drag tick — the
    /// observable symptom was the body content jumping vertically
    /// throughout the drag, which read as "wild flickering". The
    /// last height the JS reported before the drag started stays
    /// pinned; on drag-end the JS will fire one more measurement
    /// (its rAF loop is still alive) which we accept normally.
    @Environment(\.isResizingPanes) private var isResizingPanes
    let messageID: UUID
    let html: String

    @State private var contentHeight: CGFloat = 200
    /// Last width the layout pipeline allotted to the WebView while
    /// the user was *not* dragging. While `isResizingPanes` is true
    /// we pin the WebView to this width so the HTML stops reflowing
    /// on every drag tick. The surrounding container still grows /
    /// shrinks with the available space; the visual effect is "the
    /// email body stays put, the gutter around it changes". This
    /// matches how Mail.app, Things, and Notes behave during pane
    /// resizes.
    @State private var frozenWidth: CGFloat?
    /// Persisted preference: load remote images by default. Defaults to
    /// `true` per product decision — privacy is a non-goal for this app's
    /// initial audience and the silent placeholders confused users.
    /// The setting can flip back to false in Settings later.
    @AppStorage("mailclient.detail.loadRemoteImages") private var allowRemoteImages = true

    var body: some View {
        HTMLMessageBodyView(
            html: html,
            allowRemoteImages: allowRemoteImages,
            onContentHeight: { newHeight in
                // Drop height updates that arrive while the user is
                // actively resizing panes. Without this the WebView
                // reflows on every drag tick, posts a slightly
                // different height each time, and the @State update
                // re-frames the WebView vertically — visible as
                // jitter even though the user is only moving
                // horizontally.
                guard !isResizingPanes else { return }
                // Defense in depth against the resize-feedback bug:
                //  · ceil + 4 absorbs sub-pixel rounding
                //  · ignore changes < 4 px (the JS already filters at 2)
                //  · cap at 20 000 px so a runaway can't lock the UI
                let next = min(20_000, ceil(newHeight) + 4)
                if abs(next - contentHeight) >= 4 {
                    contentHeight = next
                }
            }
        )
        // Pin the WebView's width to the last steady-state value
        // during a drag. `frame(width: nil, ...)` is a no-op when
        // not resizing, so the WebView fills the proposed width
        // through the outer `maxWidth: .infinity` frame as before.
        .frame(width: isResizingPanes ? frozenWidth : nil, alignment: .leading)
        .frame(height: contentHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read the WebView's current width into `frozenWidth` only
        // when we are *not* dragging. This captures the last steady
        // width before each drag begins; on drag-start the captured
        // value freezes and stops updating until the drag ends.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BodyWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(BodyWidthPreferenceKey.self) { width in
            guard !isResizingPanes, width > 0 else { return }
            frozenWidth = width
        }
        // Reset state when the user navigates to a different message.
        .id(messageID)
    }
}

/// Captures the WKWebView's allotted width so we can freeze it
/// during a pane drag. Lives outside `HTMLBodyContainer` because
/// SwiftUI requires `PreferenceKey`s to be top-level types.
private struct BodyWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
