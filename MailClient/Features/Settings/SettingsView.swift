import SwiftUI

/// Inline settings surface — replaces the old `Settings { }` popup.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("mailclient.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("mailclient.desktop.badges") private var badgesEnabled = true
    @AppStorage("mailclient.links.external") private var openLinksExternally = true

    @State private var selectedSection: Section = .accounts
    @State private var expandedAccountID: MailAccount.ID?
    @Namespace private var sectionNamespace

    enum Section: String, CaseIterable, Identifiable {
        case accounts, general, appearance, shortcuts, about
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(DS.Color.line)
            detail
        }
        .background(DS.Color.bg)
    }

    // MARK: – Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(DS.Motion.surface) { appState.route = .mail }
                } label: {
                    DSIcon(name: .chevronLeft, size: 12)
                        .foregroundStyle(DS.Color.ink3)
                        .frame(width: 22, height: 22)
                        .dsCard(cornerRadius: 5)
                }
                .buttonStyle(.plain)
                .hoverLift()
                Text(appState.strings.settings)
                    .font(DS.Font.sans(14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Section.allCases) { section in
                    sectionRow(section)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 220)
        .background(DS.Color.surface2)
    }

    private func sectionRow(_ section: Section) -> some View {
        let isSelected = section == selectedSection
        return Button {
            withAnimation(DS.Motion.snap) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 9) {
                DSIcon(name: icon(for: section), size: 13)
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.ink3)
                    .scaleEffect(isSelected ? 1.05 : 1)
                Text(label(for: section))
                    .font(DS.Font.sans(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.ink2)
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DS.Color.selected)
                            .matchedGeometryEffect(id: "settingsSection", in: sectionNamespace)
                    }
                }
            )
            .compositingGroup()
        }
        .buttonStyle(.plain)
    }

    private func icon(for section: Section) -> DSIconName {
        switch section {
        case .accounts:   return .at
        case .general:    return .settings
        case .appearance: return .sun
        case .shortcuts:  return .command
        case .about:      return .help
        }
    }

    private func label(for section: Section) -> String {
        let zh = appState.language == .simplifiedChinese
        switch section {
        case .accounts:   return zh ? "账号" : "Accounts"
        case .general:    return zh ? "通用" : "General"
        case .appearance: return zh ? "外观" : "Appearance"
        case .shortcuts:  return zh ? "快捷键" : "Shortcuts"
        case .about:      return zh ? "关于" : "About"
        }
    }

    // MARK: – Detail

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    switch selectedSection {
                    case .accounts:   accountsPanel
                    case .general:    generalPanel
                    case .appearance: appearancePanel
                    case .shortcuts:  shortcutsPanel
                    case .about:      aboutPanel
                    }
                }
                .id(selectedSection)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 10)),
                    removal:   .opacity.combined(with: .offset(y: -10))
                ))
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(DS.Motion.surface, value: selectedSection)
    }

    // MARK: Accounts

    private var accountsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.language == .simplifiedChinese ? "邮箱账号" : "Email accounts")
                        .font(DS.Font.sans(20, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                    Text(appState.language == .simplifiedChinese
                         ? "集中管理所有已接入的邮箱，支持随时暂停或重新授权。"
                         : "Manage every connected mailbox. Pause or re-authorize at any time.")
                        .font(DS.Font.sans(12))
                        .foregroundStyle(DS.Color.ink3)
                }
                Spacer()
                Button {
                    appState.route = .accountWizard
                } label: {
                    HStack(spacing: 5) {
                        DSIcon(name: .plus, size: 11, weight: .semibold)
                        Text(appState.language == .simplifiedChinese ? "添加账号" : "Add account")
                            .font(DS.Font.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.accent)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .compositingGroup()
                }
                .buttonStyle(.plain)
                .hoverLift()
            }

            if let status = appState.mailboxStatusMessage {
                Text(status)
                    .font(DS.Font.sans(11.5))
                    .foregroundStyle(DS.Color.ink3)
            }

            if appState.accounts.isEmpty {
                EmptyStateView(
                    title: appState.strings.noAccountsTitle,
                    systemImage: "tray.2",
                    message: appState.strings.noAccountsMessage
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .dsCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.accounts.enumerated()), id: \.element.id) { index, account in
                        AccountListRow(
                            account: account,
                            isExpanded: expandedAccountID == account.id,
                            onToggle: {
                                expandedAccountID = expandedAccountID == account.id ? nil : account.id
                            },
                            onRemove: {
                                Task { await appState.removeAccount(account) }
                            }
                        )
                        if index < appState.accounts.count - 1 {
                            Divider().overlay(DS.Color.line)
                        }
                    }
                }
                .dsCard()
            }
        }
    }

    // MARK: General

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeading(title: appState.language == .simplifiedChinese ? "通用" : "General",
                         subtitle: appState.language == .simplifiedChinese ? "调整基础行为。" : "Tune baseline behaviors.")
            card {
                settingRow(label: appState.strings.displayLanguage) {
                    Picker("", selection: $appState.language) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                Divider().overlay(DS.Color.line)
                toggleRow(label: appState.strings.enableNotifications, value: $notificationsEnabled)
                Divider().overlay(DS.Color.line)
                toggleRow(label: appState.strings.showDockBadge, value: $badgesEnabled)
                Divider().overlay(DS.Color.line)
                toggleRow(label: appState.strings.openLinksInBrowser, value: $openLinksExternally)
            }
        }
    }

    // MARK: Appearance

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeading(title: appState.language == .simplifiedChinese ? "外观" : "Appearance",
                         subtitle: appState.language == .simplifiedChinese ? "界面跟随系统主题。" : "UI follows the system theme.")
            card {
                settingRow(label: appState.language == .simplifiedChinese ? "主题" : "Theme") {
                    Text(appState.language == .simplifiedChinese ? "跟随系统" : "System")
                        .font(DS.Font.sans(12))
                        .foregroundStyle(DS.Color.ink3)
                }
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeading(title: appState.language == .simplifiedChinese ? "快捷键" : "Shortcuts",
                         subtitle: appState.language == .simplifiedChinese ? "MailStream 面向键盘用户设计。" : "MailStream is keyboard-first.")
            card {
                shortcutRow(label: appState.strings.compose, keys: ["⌘", "N"])
                Divider().overlay(DS.Color.line)
                shortcutRow(label: appState.strings.refresh, keys: ["⌘", "R"])
                Divider().overlay(DS.Color.line)
                shortcutRow(label: appState.strings.commandPalette, keys: ["⌘", "K"])
                Divider().overlay(DS.Color.line)
                shortcutRow(label: appState.strings.settings, keys: ["⌘", ","])
            }
        }
    }

    // MARK: About

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeading(title: "MailStream",
                         subtitle: appState.language == .simplifiedChinese ? "版本 0.1 · 面向专业用户的桌面邮箱客户端" : "v0.1 · a desktop mail client for professionals")
            card {
                settingRow(label: appState.language == .simplifiedChinese ? "版本" : "Version") {
                    Text("0.1.0").font(DS.Font.mono(11)).foregroundStyle(DS.Color.ink3)
                }
                Divider().overlay(DS.Color.line)
                settingRow(label: appState.language == .simplifiedChinese ? "官网" : "Website") {
                    Text("mailstream.app").font(DS.Font.mono(11)).foregroundStyle(DS.Color.accent)
                }
            }
        }
    }

    // MARK: Helpers

    private func panelHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.Font.sans(20, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Text(subtitle)
                .font(DS.Font.sans(12))
                .foregroundStyle(DS.Color.ink3)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.dsCard()
    }

    private func settingRow<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(DS.Font.sans(12.5, weight: .medium))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private func toggleRow(label: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(DS.Font.sans(12.5, weight: .medium))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private func shortcutRow(label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(DS.Font.sans(12.5, weight: .medium))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Kbd(text: $0) }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }
}

// MARK: - Account row

private struct AccountListRow: View {
    @EnvironmentObject private var appState: AppState
    let account: MailAccount
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(
                    initials: String((account.displayName.isEmpty ? account.emailAddress : account.displayName).prefix(2)),
                    size: 34,
                    providerColor: ProviderPalette.color(for: account.providerType)
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                            .font(DS.Font.sans(13, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                        statusBadge
                    }
                    Text(account.emailAddress)
                        .font(DS.Font.mono(11))
                        .foregroundStyle(DS.Color.ink3)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(syncText)
                        .font(DS.Font.sans(11))
                        .foregroundStyle(DS.Color.ink3)
                    Text(account.providerType.displayName(language: appState.language))
                        .font(DS.Font.sans(10, weight: .medium))
                        .foregroundStyle(DS.Color.ink4)
                }

                // mock toggle — see AppState.toggleAccountEnabled. Persists in
                // a UI-side disabled set; doesn't reach MailSyncService yet.
                Toggle("", isOn: Binding(
                    get: { appState.isAccountDisabled(account) == false },
                    set: { _ in
                        withAnimation(DS.Motion.surface) {
                            appState.toggleAccountEnabled(account)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                Button(action: { withAnimation(DS.Motion.surface) { onToggle() } }) {
                    DSIcon(name: .chevronRight, size: 11)
                        .foregroundStyle(DS.Color.ink3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(DS.Motion.surface) { onToggle() } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: appState.language == .simplifiedChinese ? "同步频率" : "Sync interval",
                              value: appState.language == .simplifiedChinese ? "每 5 分钟" : "Every 5 min")
                    detailRow(label: appState.language == .simplifiedChinese ? "通知" : "Notifications",
                              value: appState.language == .simplifiedChinese ? "新邮件时提醒" : "On new mail")
                    detailRow(label: appState.language == .simplifiedChinese ? "签名" : "Signature",
                              value: account.displayName.isEmpty ? "—" : account.displayName)

                    HStack {
                        Spacer()
                        Button {
                            Task { await appState.refreshMailbox() }
                        } label: {
                            HStack(spacing: 5) {
                                DSIcon(name: .refresh, size: 10)
                                Text(appState.strings.syncNow)
                                    .font(DS.Font.sans(11.5, weight: .medium))
                            }
                            .foregroundStyle(DS.Color.ink2)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .dsCard(cornerRadius: 6, fill: DS.Color.surface2)
                        }
                        .buttonStyle(.plain)

                        Button(action: onRemove) {
                            Text(appState.strings.removeAccount)
                                .font(DS.Font.sans(11.5, weight: .medium))
                                .foregroundStyle(DS.Color.red)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(DS.Color.red.opacity(0.10))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .compositingGroup()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal:   .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
    }

    private var statusBadge: some View {
        let zh = appState.language == .simplifiedChinese
        let (text, tint): (String, Color) = {
            switch account.status {
            case .connected:    return (zh ? "已连接" : "Connected", DS.Color.green)
            case .syncing:      return (zh ? "同步中" : "Syncing", DS.Color.accent)
            case .error:        return (zh ? "需重新授权" : "Re-authorize", DS.Color.amber)
            case .disconnected: return (zh ? "未连接" : "Disconnected", DS.Color.ink4)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(DS.Font.sans(10, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
        .clipShape(Capsule(style: .continuous))
        .compositingGroup()
    }

    private var syncText: String {
        if let last = account.lastSyncedAt {
            let seconds = Int(Date().timeIntervalSince(last))
            if seconds < 60 { return appState.strings.syncedJustNow }
            if seconds < 3600 { return appState.strings.syncedMinutesAgo(seconds / 60) }
            return appState.strings.syncedHoursAgo(seconds / 3600)
        }
        return appState.strings.neverSynced
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Font.sans(11.5))
                .foregroundStyle(DS.Color.ink3)
            Spacer()
            Text(value)
                .font(DS.Font.sans(11.5, weight: .medium))
                .foregroundStyle(DS.Color.ink2)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .dsCard(cornerRadius: 6, fill: DS.Color.surface2, stroke: nil)
    }
}
