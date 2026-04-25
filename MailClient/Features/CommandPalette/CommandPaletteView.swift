import SwiftUI

/// ⌘K command palette — matches the design's centered overlay.
struct CommandPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isQueryFocused: Bool
    @State private var query = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                queryField
                Divider().overlay(DS.Color.line)
                results
                Divider().overlay(DS.Color.line)
                footer
            }
            .frame(width: 640)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.lineStrong, lineWidth: DS.Stroke.hairline)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 44, x: 0, y: 16)
            .onAppear { isQueryFocused = true }
        }
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            DSIcon(name: .search, size: 14)
                .foregroundStyle(DS.Color.ink3)
            TextField("发票 · 邮件主题 · 联系人…", text: $query)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(13))
                .focused($isQueryFocused)
                .onSubmit { dismiss() }
            Kbd(text: "esc")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    @ViewBuilder
    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                group(title: "建议") {
                    row(icon: .pencil, label: appState.strings.compose, kbd: ["C"], highlighted: true) {
                        appState.openCompose()
                        dismiss()
                    }
                    row(icon: .search, label: appState.language == .simplifiedChinese ? "搜索所有账号的邮件…" : "Search all accounts…", kbd: ["⌘", "⇧F"]) {
                        appState.route = .search
                        dismiss()
                    }
                    row(icon: .refresh, label: "同步全部账号", kbd: ["⌘", "R"]) {
                        Task { await appState.refreshMailbox() }
                        dismiss()
                    }
                }
                group(title: "跳转到") {
                    row(icon: .inbox, label: appState.strings.inbox, kbd: ["G", "I"], accessory: "\(appState.messages.count)") {
                        appState.selectedSidebarItem = .allMail
                        dismiss()
                    }
                    row(icon: .flame, label: appState.strings.chipPriority, kbd: ["G", "P"], accessory: "\(appState.messages.filter(\.isPriority).count)") {
                        appState.selectedSidebarItem = .priority
                        dismiss()
                    }
                    row(icon: .clock, label: appState.strings.snooze, kbd: ["G", "S"]) { dismiss() }
                    row(icon: .send, label: appState.strings.sent, kbd: ["G", "E"]) {
                        appState.selectedSidebarItem = .sent
                        dismiss()
                    }
                }
                if appState.accounts.isEmpty == false {
                    group(title: "最近联系人") {
                        ForEach(appState.accounts.prefix(4)) { acc in
                            contactRow(acc)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 480)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                DSIcon(name: .arrowDown, size: 10)
                DSIcon(name: .arrowUp, size: 10)
                Text("选择")
            }
            HStack(spacing: 4) {
                Kbd(text: "↵")
                Text("执行")
            }
            HStack(spacing: 4) {
                Kbd(text: "⌘↵")
                Text("新窗口打开")
            }
            Spacer()
            Text("MailStream").font(DS.Font.sans(11, weight: .semibold))
        }
        .font(DS.Font.sans(11))
        .foregroundStyle(DS.Color.ink3)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(DS.Color.surface2)
    }

    @ViewBuilder
    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DS.Font.sans(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DS.Color.ink4)
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 2)
            content()
        }
    }

    private func row(icon: DSIconName, label: String, kbd: [String], accessory: String? = nil, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DSIcon(name: icon, size: 13)
                    .foregroundStyle(DS.Color.ink3)
                Text(label)
                    .font(DS.Font.sans(12.5, weight: highlighted ? .semibold : .medium))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                if let accessory {
                    Text(accessory)
                        .font(DS.Font.mono(11))
                        .foregroundStyle(DS.Color.ink4)
                        .padding(.trailing, 6)
                }
                HStack(spacing: 3) {
                    ForEach(kbd, id: \.self) { k in Kbd(text: k) }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(highlighted ? DS.Color.hover : .clear)
        }
        .buttonStyle(.plain)
    }

    private func contactRow(_ account: MailAccount) -> some View {
        HStack(spacing: 10) {
            Avatar(
                initials: account.displayName.isEmpty ? "—" : String(account.displayName.prefix(2)),
                size: 24,
                providerColor: ProviderPalette.color(for: account.providerType)
            )
            Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                .font(DS.Font.sans(12.5, weight: .medium))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            Text(account.emailAddress)
                .font(DS.Font.mono(11))
                .foregroundStyle(DS.Color.ink4)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func dismiss() { appState.isShowingCommandPalette = false }
}
