import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("mailclient.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("mailclient.desktop.badges") private var badgesEnabled = true
    @AppStorage("mailclient.links.external") private var openLinksExternally = true

    @State private var providerType: MailProviderType = .qq
    @State private var accountName = ""
    @State private var emailAddress = ""
    @State private var secret = ""
    @State private var accountSearchText = ""
    @State private var isShowingAccountSetup = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 292), spacing: 14)
    ]

    private var filteredAccounts: [MailAccount] {
        guard accountSearchText.isEmpty == false else {
            return appState.accounts
        }

        let query = accountSearchText.lowercased()
        return appState.accounts.filter {
            $0.displayName.lowercased().contains(query)
                || $0.emailAddress.lowercased().contains(query)
                || $0.providerType.displayName(language: appState.language).lowercased().contains(query)
        }
    }

    private var connectButtonDisabled: Bool {
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty
            || trimmedSecret.isEmpty
            || appState.isProviderAvailable(providerType) == false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                accountsGrid

                if isShowingAccountSetup || appState.accounts.isEmpty {
                    addAccountPanel
                }

                preferencesPanel
            }
            .padding(22)
        }
        .frame(width: 840, height: 640)
        .background(AppTheme.panel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                searchField
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.strings.connectedAccounts)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(appState.strings.connectedAccountsSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if let mailboxStatusMessage = appState.mailboxStatusMessage {
                Text(mailboxStatusMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textTertiary)

            TextField(appState.strings.searchAccounts, text: $accountSearchText)
                .textFieldStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.panelMuted.opacity(0.72))
        )
    }

    private var accountsGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            if filteredAccounts.isEmpty {
                EmptyStateView(
                    title: appState.strings.noAccountsTitle,
                    systemImage: "tray.2",
                    message: appState.strings.noAccountsMessage
                )
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.panelElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )
            } else {
                ForEach(filteredAccounts) { account in
                    AccountCardView(account: account)
                        .environmentObject(appState)
                }
            }

            AddAccountCardView(isExpanded: isShowingAccountSetup) {
                isShowingAccountSetup = true
            }
            .environmentObject(appState)
        }
    }

    private var addAccountPanel: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(appState.strings.accountSetup)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(appState.strings.plannedProviderHint)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 150), spacing: 10)], spacing: 10) {
                    ForEach(MailProviderType.allCases) { provider in
                        ProviderOptionCardView(
                            provider: provider,
                            isSelected: provider == providerType,
                            isAvailable: appState.isProviderAvailable(provider)
                        ) {
                            providerType = provider
                        }
                    }
                }
            }
            .frame(maxWidth: 310, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(appState.strings.connectNewAccount)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(appState.strings.selectService)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    providerBadge(providerType)
                }

                HStack(spacing: 10) {
                    Image(systemName: providerType.systemImageName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(providerTint(for: providerType))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(providerTint(for: providerType).opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(providerType.displayName(language: appState.language))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(appState.isProviderAvailable(providerType) ? appState.strings.availableNow : appState.strings.comingSoon)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsFieldLabel(title: appState.strings.accountName)
                    TextField(appState.strings.accountNamePlaceholder, text: $accountName)
                        .textFieldStyle(AccountSettingsTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsFieldLabel(title: appState.strings.emailAddress)
                    TextField(appState.strings.emailAddress, text: $emailAddress)
                        .textFieldStyle(AccountSettingsTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsFieldLabel(title: appState.strings.accountSecret)
                    SecureField(appState.strings.accountSecret, text: $secret)
                        .textFieldStyle(AccountSettingsTextFieldStyle())
                }

                HStack(spacing: 12) {
                    Button(appState.strings.saveAndConnect) {
                        Task {
                            await appState.connectAccount(
                                providerType: providerType,
                                displayName: accountName,
                                emailAddress: emailAddress,
                                secret: secret
                            )

                            if appState.isProviderAvailable(providerType) {
                                accountName = ""
                                emailAddress = ""
                                secret = ""
                                isShowingAccountSetup = false
                            }
                        }
                    }
                    .buttonStyle(MailStreaPrimaryButtonStyle())
                    .frame(width: 172)
                    .disabled(connectButtonDisabled)

                    Spacer()

                    Button(appState.strings.syncNow) {
                        Task {
                            await appState.refreshMailbox()
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.activeAccounts.isEmpty || appState.isRefreshingMailbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.panelElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 1)
        )
    }

    private var preferencesPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(appState.strings.languageSection)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Picker(appState.strings.displayLanguage, selection: $appState.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text(appState.strings.general)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Toggle(appState.strings.enableNotifications, isOn: $notificationsEnabled)
                Toggle(appState.strings.showDockBadge, isOn: $badgesEnabled)
                Toggle(appState.strings.openLinksInBrowser, isOn: $openLinksExternally)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.panelElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.panelBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func providerBadge(_ provider: MailProviderType) -> some View {
        let isAvailable = appState.isProviderAvailable(provider)
        Text(isAvailable ? appState.strings.liveConnector : appState.strings.comingSoon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isAvailable ? AppTheme.success : AppTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isAvailable ? AppTheme.successSurface : AppTheme.panelMuted.opacity(0.82))
            )
    }

    private func providerTint(for provider: MailProviderType) -> Color {
        switch provider {
        case .qq:
            return AppTheme.providerQQ
        case .gmail:
            return AppTheme.providerGmail
        case .outlook:
            return AppTheme.providerOutlook
        case .icloud:
            return AppTheme.providerICloud
        case .customIMAPSMTP:
            return AppTheme.providerCustom
        }
    }
}

private struct AccountCardView: View {
    @EnvironmentObject private var appState: AppState

    let account: MailAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(providerTint.opacity(0.15))
                        .frame(width: 38, height: 38)

                    Image(systemName: account.providerType.systemImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(providerTint)
                }

                Spacer()

                Button {
                    Task {
                        await appState.removeAccount(account)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(account.emailAddress)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(account.providerType.displayName(language: appState.language))
                    Spacer()
                    Text(appState.isProviderAvailable(account.providerType) ? appState.strings.availableNow : appState.strings.comingSoon)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 5)

                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(providerTint)
                            .frame(width: geometry.size.width * progressValue, height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.panelElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    appState.selectedAccountID == account.id ? providerTint.opacity(0.42) : AppTheme.panelBorder,
                    lineWidth: appState.selectedAccountID == account.id ? 1.4 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            appState.selectedAccountID = account.id
        }
    }

    private var providerTint: Color {
        switch account.providerType {
        case .qq:
            return AppTheme.providerQQ
        case .gmail:
            return AppTheme.providerGmail
        case .outlook:
            return AppTheme.providerOutlook
        case .icloud:
            return AppTheme.providerICloud
        case .customIMAPSMTP:
            return AppTheme.providerCustom
        }
    }

    private var progressValue: CGFloat {
        switch account.providerType {
        case .qq:
            return 0.46
        case .gmail:
            return 0.72
        case .outlook:
            return 0.22
        case .icloud:
            return 0.94
        case .customIMAPSMTP:
            return 0.36
        }
    }

    private var statusColor: Color {
        switch account.status {
        case .connected:
            return AppTheme.successBright
        case .syncing:
            return AppTheme.info
        case .error:
            return AppTheme.destructive
        case .disconnected:
            return AppTheme.textTertiary
        }
    }

    private var statusText: String {
        switch account.status {
        case .connected:
            if let lastSyncedAt = account.lastSyncedAt {
                return relativeSyncText(from: lastSyncedAt)
            }
            return appState.strings.accountConnected
        case .syncing:
            return appState.strings.syncingMailbox
        case .error:
            return account.lastErrorMessage ?? appState.strings.connectionError
        case .disconnected:
            return appState.strings.neverSynced
        }
    }

    private func relativeSyncText(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return appState.strings.syncedJustNow
        }
        if seconds < 3600 {
            return appState.strings.syncedMinutesAgo(seconds / 60)
        }
        return appState.strings.syncedHoursAgo(seconds / 3600)
    }
}

private struct AddAccountCardView: View {
    @EnvironmentObject private var appState: AppState

    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.softIconSurface)
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                VStack(spacing: 4) {
                    Text(appState.strings.connectNewAccount)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("QQ, Gmail, Outlook, iCloud, IMAP / SMTP")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 176)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.panelElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isExpanded ? AppTheme.textPrimary.opacity(0.24) : AppTheme.panelBorder,
                        style: StrokeStyle(lineWidth: 1.2, dash: [7, 7])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderOptionCardView: View {
    @EnvironmentObject private var appState: AppState

    let provider: MailProviderType
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: provider.systemImageName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Circle()
                        .fill(isAvailable ? AppTheme.successBright : AppTheme.textTertiary.opacity(0.6))
                        .frame(width: 7, height: 7)
                }

                Text(provider.displayName(language: appState.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(isAvailable ? appState.strings.availableNow : appState.strings.comingSoon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.10) : AppTheme.panelMuted.opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.42) : AppTheme.panelBorder, lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        switch provider {
        case .qq:
            return AppTheme.providerQQ
        case .gmail:
            return AppTheme.providerGmail
        case .outlook:
            return AppTheme.providerOutlook
        case .icloud:
            return AppTheme.providerICloud
        case .customIMAPSMTP:
            return AppTheme.providerCustom
        }
    }
}

private struct SettingsFieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary)
    }
}

private struct AccountSettingsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.panelMuted.opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppTheme.panelBorder, lineWidth: 1)
            )
    }
}
