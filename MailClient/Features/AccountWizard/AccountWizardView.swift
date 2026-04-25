import SwiftUI

/// Account connection wizard — provider picker + OAuth/IMAP action panel.
struct AccountWizardView: View {
    @EnvironmentObject private var appState: AppState

    @State private var providerType: MailProviderType = .gmail
    @State private var currentStep: WizardStep = .provider
    @State private var displayName = ""
    @State private var emailAddress = ""
    @State private var secret = ""

    enum WizardStep: Int, CaseIterable, Identifiable {
        case provider, authorize, sync, done
        var id: Int { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            stepper
            Divider().overlay(DS.Color.line)
            content
        }
        .background(DS.Color.surface)
        .onAppear { providerType = appState.pendingWizardProvider }
    }

    // MARK: – Stepper

    private var stepper: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 4) {
                ForEach(WizardStep.allCases) { step in
                    stepRow(step)
                }
            }

            Spacer()

            helpPanel
        }
        .padding(20)
        .frame(width: 260)
        .background(DS.Color.surface2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                appState.route = appState.accounts.isEmpty ? .onboarding : .settings
            } label: {
                DSIcon(name: .chevronLeft, size: 12)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DS.Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
                    )
            }
            .buttonStyle(.plain)
            Text(isChinese ? "添加邮箱账号" : "Add an account")
                .font(DS.Font.sans(13, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Spacer()
        }
    }

    private func stepRow(_ step: WizardStep) -> some View {
        let index = step.rawValue
        let current = currentStep.rawValue
        let isActive = index == current
        let isDone = index < current

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isActive ? DS.Color.accent : (isDone ? DS.Color.green : DS.Color.surface))
                    .frame(width: 20, height: 20)
                Circle()
                    .stroke(DS.Color.lineStrong, lineWidth: isActive ? 0 : DS.Stroke.hairline)
                    .frame(width: 20, height: 20)
                if isDone {
                    DSIcon(name: .check, size: 9, weight: .bold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(DS.Font.mono(10, weight: .bold))
                        .foregroundStyle(isActive ? .white : DS.Color.ink3)
                }
            }
            Text(stepLabel(step))
                .font(DS.Font.sans(12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.Color.ink : DS.Color.ink3)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? DS.Color.selected : .clear)
        )
    }

    private func stepLabel(_ step: WizardStep) -> String {
        switch (step, isChinese) {
        case (.provider,  true):  return "选择服务商"
        case (.authorize, true):  return "授权登录"
        case (.sync,      true):  return "同步设置"
        case (.done,      true):  return "完成"
        case (.provider,  false): return "Choose provider"
        case (.authorize, false): return "Authorize"
        case (.sync,      false): return "Sync settings"
        case (.done,      false): return "Done"
        }
    }

    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DSIcon(name: .shield, size: 11)
                    .foregroundStyle(DS.Color.green)
                Text(isChinese ? "隐私承诺" : "Privacy")
                    .font(DS.Font.sans(11, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
            }
            Text(isChinese
                 ? "凭证仅保存在本机 Keychain，邮件正文不会上传。"
                 : "Credentials stay in your local Keychain. Your mail never leaves the device.")
                .font(DS.Font.sans(11))
                .foregroundStyle(DS.Color.ink3)
                .lineSpacing(2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
        )
    }

    // MARK: – Right content

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .provider:  providerStep
        case .authorize: authorizeStep
        case .sync:      syncStep
        case .done:      doneStep
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                title: isChinese ? "选择你的邮箱服务商" : "Pick your mail provider",
                subtitle: isChinese
                    ? "支持主流服务商的一键授权，或通过 IMAP/SMTP 接入自定义服务器。"
                    : "One-tap OAuth for major providers, or connect via IMAP/SMTP."
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(MailProviderType.allCases) { provider in
                    providerCard(provider)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    appState.pendingWizardProvider = providerType
                    currentStep = .authorize
                } label: {
                    HStack(spacing: 5) {
                        Text(isChinese ? "继续" : "Continue")
                            .font(DS.Font.sans(12, weight: .semibold))
                        DSIcon(name: .arrowRight, size: 11)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.accent)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func providerCard(_ provider: MailProviderType) -> some View {
        let isSelected = provider == providerType
        let isAvailable = appState.isProviderAvailable(provider)
        let tint = ProviderPalette.color(for: provider)

        return Button {
            providerType = provider
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: provider.systemImageName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    if isAvailable {
                        pill(text: isChinese ? "推荐" : "Recommended", tint: DS.Color.green)
                    } else {
                        pill(text: isChinese ? "即将支持" : "Soon", tint: DS.Color.ink4)
                    }
                }

                Text(provider.displayName(language: appState.language))
                    .font(DS.Font.sans(13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)

                Text(providerHint(provider))
                    .font(DS.Font.sans(11))
                    .foregroundStyle(DS.Color.ink3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.08) : DS.Color.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.6) : DS.Color.line, lineWidth: isSelected ? 1.2 : DS.Stroke.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private func providerHint(_ provider: MailProviderType) -> String {
        switch (provider, isChinese) {
        case (.gmail, true):  return "Google 账号 OAuth 授权"
        case (.gmail, false): return "Google OAuth sign-in"
        case (.outlook, true):  return "Microsoft 365 / Outlook OAuth"
        case (.outlook, false): return "Microsoft 365 / Outlook OAuth"
        case (.icloud, true):  return "Apple 应用专用密码"
        case (.icloud, false): return "Apple app-specific password"
        case (.qq, true):  return "QQ / 163 / 126 IMAP 授权码"
        case (.qq, false): return "QQ / 163 IMAP authorization"
        case (.customIMAPSMTP, true):  return "自定义 IMAP / SMTP 服务器"
        case (.customIMAPSMTP, false): return "Custom IMAP / SMTP server"
        }
    }

    private var authorizeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                title: isChinese ? "授权登录 \(providerType.displayName(language: appState.language))" : "Authorize \(providerType.displayName(language: appState.language))",
                subtitle: appState.isProviderAvailable(providerType)
                    ? (isChinese ? "填写账号信息后即可完成连接。" : "Fill in account details to complete the connection.")
                    : (isChinese ? "该服务商暂未完全支持，你可以预填信息，待上线后自动接入。" : "This provider isn't live yet — information will be used when available.")
            )

            formField(title: isChinese ? "账户名称" : "Account name",
                      placeholder: isChinese ? "比如：工作邮箱" : "Work mail",
                      text: $displayName)

            formField(title: isChinese ? "邮箱地址" : "Email address",
                      placeholder: "name@example.com",
                      text: $emailAddress)

            formField(title: isChinese ? "授权码 / 应用专用密码" : "App password / authorization code",
                      placeholder: "••••••••",
                      text: $secret,
                      secure: true)

            Spacer()

            HStack {
                Button { currentStep = .provider } label: {
                    Text(isChinese ? "上一步" : "Back")
                        .font(DS.Font.sans(12, weight: .medium))
                        .foregroundStyle(DS.Color.ink3)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    currentStep = .sync
                } label: {
                    HStack(spacing: 5) {
                        Text(isChinese ? "下一步" : "Next")
                            .font(DS.Font.sans(12, weight: .semibold))
                        DSIcon(name: .arrowRight, size: 11)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.accent.opacity(connectDisabled ? 0.5 : 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(connectDisabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var syncStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeading(
                title: isChinese ? "同步设置" : "Sync settings",
                subtitle: isChinese ? "你可以稍后在设置中调整。" : "You can tweak these later in Settings."
            )

            VStack(alignment: .leading, spacing: 10) {
                syncRow(icon: .refresh, title: isChinese ? "同步频率" : "Sync interval", value: isChinese ? "每 5 分钟" : "Every 5 min")
                syncRow(icon: .bell, title: isChinese ? "新邮件通知" : "New mail notifications", value: isChinese ? "开启" : "On")
                syncRow(icon: .download, title: isChinese ? "附件" : "Attachments", value: isChinese ? "按需下载" : "On demand")
            }

            Spacer()

            HStack {
                Button { currentStep = .authorize } label: {
                    Text(isChinese ? "上一步" : "Back")
                        .font(DS.Font.sans(12, weight: .medium))
                        .foregroundStyle(DS.Color.ink3)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await connect() }
                } label: {
                    Text(isChinese ? "完成接入" : "Finish & connect")
                        .font(DS.Font.sans(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(DS.Color.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(DS.Color.green.opacity(0.16)).frame(width: 56, height: 56)
                DSIcon(name: .check, size: 22, weight: .bold)
                    .foregroundStyle(DS.Color.green)
            }
            Text(isChinese ? "账号已接入" : "Account connected")
                .font(DS.Font.sans(15, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Text(isChinese ? "正在同步最新邮件…" : "Syncing latest mail…")
                .font(DS.Font.sans(12))
                .foregroundStyle(DS.Color.ink3)

            Button {
                appState.route = .mail
            } label: {
                Text(isChinese ? "进入收件箱" : "Open inbox")
                    .font(DS.Font.sans(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Helpers

    private func stepHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.Font.sans(17, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Text(subtitle)
                .font(DS.Font.sans(12))
                .foregroundStyle(DS.Color.ink3)
        }
    }

    @ViewBuilder
    private func formField(title: String, placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(DS.Font.sans(10.5, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.ink4)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(DS.Font.sans(13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.Color.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
            )
        }
    }

    private func syncRow(icon: DSIconName, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            DSIcon(name: icon, size: 13)
                .foregroundStyle(DS.Color.ink3)
            Text(title)
                .font(DS.Font.sans(12, weight: .medium))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            Text(value)
                .font(DS.Font.sans(11.5))
                .foregroundStyle(DS.Color.ink3)
            DSIcon(name: .chevronRight, size: 10)
                .foregroundStyle(DS.Color.ink4)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Color.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
        )
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(text)
            .font(DS.Font.sans(9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous).fill(tint.opacity(0.12))
            )
    }

    private var connectDisabled: Bool {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func connect() async {
        await appState.connectAccount(
            providerType: providerType,
            displayName: displayName.isEmpty ? emailAddress : displayName,
            emailAddress: emailAddress,
            secret: secret
        )
        currentStep = .done
    }

    private var isChinese: Bool { appState.language == .simplifiedChinese }
}
