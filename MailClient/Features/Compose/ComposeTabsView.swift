import SwiftUI

/// Multi-draft tabbed compose surface (replaces the modal sheet).
struct ComposeTabsView: View {
    @EnvironmentObject private var appState: AppState

    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(DS.Color.line)
            if let id = appState.activeDraftID,
               let index = appState.composeDrafts.firstIndex(where: { $0.id == id }) {
                ComposeEditor(draftID: id, draft: $appState.composeDrafts[index])
                    .id(id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal:   .opacity.combined(with: .move(edge: .leading))
                    ))
            } else {
                EmptyStateView(
                    title: isChinese ? "没有打开的草稿" : "No open draft",
                    systemImage: "square.and.pencil",
                    message: isChinese ? "在侧栏点击「写邮件」开始新草稿。" : "Tap Compose in the sidebar to start one."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DS.Color.bg)
        .animation(DS.Motion.surface, value: appState.activeDraftID)
        .animation(DS.Motion.snap, value: appState.composeDrafts.map(\.id))
    }

    // MARK: – Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            Button {
                appState.route = .mail
            } label: {
                DSIcon(name: .chevronLeft, size: 12)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(appState.composeDrafts) { draft in
                        tabChip(for: draft)
                    }
                }
                .padding(.horizontal, 4)
            }

            Button {
                appState.openCompose()
            } label: {
                DSIcon(name: .plus, size: 11)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DS.Color.surface2)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)

            Spacer()
        }
        .frame(height: 38)
        .background(DS.Color.surface2)
    }

    private func tabChip(for draft: ComposeDraft) -> some View {
        let isActive = draft.id == appState.activeDraftID
        let title = draft.subject.isEmpty
            ? (isChinese ? "新草稿" : "New draft")
            : draft.subject

        return HStack(spacing: 6) {
            DSIcon(name: .pencil, size: 10)
                .foregroundStyle(isActive ? DS.Color.accent : DS.Color.ink3)
            Text(title)
                .font(DS.Font.sans(11.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.Color.ink : DS.Color.ink2)
                .lineLimit(1)
                .frame(maxWidth: 160)
            Button {
                appState.closeCompose(draft.id)
            } label: {
                DSIcon(name: .close, size: 9)
                    .foregroundStyle(DS.Color.ink4)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Color.surface)
                        .matchedGeometryEffect(id: "composeTabBg", in: tabNamespace)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
                        .matchedGeometryEffect(id: "composeTabBorder", in: tabNamespace)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DS.Motion.snap) {
                appState.activeDraftID = draft.id
            }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private var isChinese: Bool { appState.language == .simplifiedChinese }
}

// MARK: - Editor

private struct ComposeEditor: View {
    @EnvironmentObject private var appState: AppState
    let draftID: ComposeDraft.ID
    @Binding var draft: ComposeDraft

    @State private var isSending = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fromRow
            Divider().overlay(DS.Color.line)
            recipientRow
            if draft.showCcBcc {
                Divider().overlay(DS.Color.line)
                ccRow
                Divider().overlay(DS.Color.line)
                bccRow
            }
            Divider().overlay(DS.Color.line)
            subjectRow
            Divider().overlay(DS.Color.line)
            bodyEditor
            Divider().overlay(DS.Color.line)
            footer
        }
        .background(DS.Color.surface)
    }

    private var fromRow: some View {
        HStack(spacing: 10) {
            label(text: isChinese ? "发件" : "FROM")
            Menu {
                ForEach(appState.accounts) { acc in
                    Button(acc.displayName.isEmpty ? acc.emailAddress : acc.displayName) {
                        draft.fromAccountID = acc.id
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let acc = currentAccount {
                        ProviderDot(color: ProviderPalette.color(for: acc.providerType), size: 6, haloed: true)
                        Text(acc.displayName.isEmpty ? acc.emailAddress : acc.displayName)
                            .font(DS.Font.sans(12, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                        Text(acc.emailAddress)
                            .font(DS.Font.mono(11))
                            .foregroundStyle(DS.Color.ink3)
                    } else {
                        Text(isChinese ? "选择账号" : "Pick an account")
                            .font(DS.Font.sans(12, weight: .medium))
                            .foregroundStyle(DS.Color.ink3)
                    }
                    DSIcon(name: .chevronDown, size: 9)
                        .foregroundStyle(DS.Color.ink4)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DS.Color.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var recipientRow: some View {
        HStack(spacing: 10) {
            label(text: isChinese ? "收件" : "TO")
            TextField("name@example.com", text: $draft.to)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(13))
                .foregroundStyle(DS.Color.ink)
            Button {
                draft.showCcBcc.toggle()
            } label: {
                Text(draft.showCcBcc
                     ? (isChinese ? "隐藏抄送" : "Hide CC")
                     : (isChinese ? "抄送 / 密送" : "CC / BCC"))
                    .font(DS.Font.sans(11, weight: .medium))
                    .foregroundStyle(DS.Color.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var ccRow: some View {
        HStack(spacing: 10) {
            label(text: "CC")
            TextField("", text: $draft.cc)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(13))
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var bccRow: some View {
        HStack(spacing: 10) {
            label(text: "BCC")
            TextField("", text: $draft.bcc)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(13))
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var subjectRow: some View {
        HStack(spacing: 10) {
            label(text: isChinese ? "主题" : "SUBJECT")
            TextField(isChinese ? "邮件主题" : "Subject", text: $draft.subject)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(14, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft.body)
                .font(DS.Font.sans(13.5))
                .foregroundStyle(DS.Color.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if draft.body.isEmpty {
                Text(isChinese ? "写点什么…" : "Start writing…")
                    .font(DS.Font.sans(13.5))
                    .foregroundStyle(DS.Color.ink4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            IconButton(icon: .bold)
            IconButton(icon: .italic)
            IconButton(icon: .link)
            IconButton(icon: .list)
            IconButton(icon: .paperclip)

            Text(isChinese ? "草稿自动保存 · 刚刚" : "Draft saved · just now")
                .font(DS.Font.sans(11))
                .foregroundStyle(DS.Color.ink4)
                .padding(.leading, 10)

            if let statusMessage {
                Text(statusMessage)
                    .font(DS.Font.sans(11))
                    .foregroundStyle(DS.Color.red)
                    .padding(.leading, 8)
            }

            Spacer()

            Button {
                // schedule send placeholder
            } label: {
                HStack(spacing: 5) {
                    DSIcon(name: .clock, size: 11)
                    Text(isChinese ? "安排发送" : "Schedule")
                        .font(DS.Font.sans(12, weight: .medium))
                }
                .foregroundStyle(DS.Color.ink2)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
                )
            }
            .buttonStyle(.plain)

            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 5) {
                    DSIcon(name: .send, size: 11)
                    Text(isSending ? (isChinese ? "发送中…" : "Sending…") : (isChinese ? "发送" : "Send"))
                        .font(DS.Font.sans(12, weight: .semibold))
                    Kbd(text: "⌘↵")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.accent.opacity(sendDisabled ? 0.5 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
            .keyboardShortcut(.return, modifiers: .command)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(DS.Color.surface2)
    }

    private func label(text: String) -> some View {
        Text(text)
            .font(DS.Font.sans(10.5, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(DS.Color.ink4)
            .frame(width: 56, alignment: .leading)
    }

    private var currentAccount: MailAccount? {
        appState.accounts.first { $0.id == draft.fromAccountID } ?? appState.accounts.first
    }

    private var sendDisabled: Bool {
        isSending
            || draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        guard isSending == false else { return }
        isSending = true
        statusMessage = nil
        defer { isSending = false }
        do {
            try await appState.sendMail(to: draft.to, subject: draft.subject, body: draft.body)
            appState.closeCompose(draftID)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var isChinese: Bool { appState.language == .simplifiedChinese }
}
