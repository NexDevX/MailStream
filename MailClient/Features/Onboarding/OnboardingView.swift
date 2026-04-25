import SwiftUI

/// First-launch onboarding — shown when no accounts are connected yet.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.chromeTop, DS.Color.chromeBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                brandMark
                headline
                providerRow
                actions
                featureBadges
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 44, x: 0, y: 18)
        }
    }

    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.13), Color(white: 0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 64, height: 64)
            Text("M")
                .font(DS.Font.mono(28, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text("MailStream")
                .font(DS.Font.sans(22, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Text(isChinese
                 ? "一个面向专业用户的桌面邮箱聚合客户端。\n将所有账号集中管理，用键盘高效处理信息。"
                 : "A desktop email aggregator for professionals.\nManage every account in one place, keyboard-first.")
                .font(DS.Font.sans(13))
                .foregroundStyle(DS.Color.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private var providerRow: some View {
        HStack(spacing: 10) {
            ForEach(MailProviderType.allCases) { provider in
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ProviderPalette.color(for: provider).opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: provider.systemImageName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ProviderPalette.color(for: provider))
                    }
                    Text(provider.displayName(language: appState.language))
                        .font(DS.Font.sans(10, weight: .medium))
                        .foregroundStyle(DS.Color.ink3)
                        .lineLimit(1)
                }
                .frame(width: 72)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                appState.route = .accountWizard
            } label: {
                HStack(spacing: 6) {
                    Text(isChinese ? "添加第一个邮箱账号" : "Add your first account")
                        .font(DS.Font.sans(13, weight: .semibold))
                    DSIcon(name: .arrowRight, size: 12)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.accent)
                )
            }
            .buttonStyle(.plain)

            Button {
                appState.route = .mail
            } label: {
                Text(isChinese ? "先看看界面 →" : "Preview the app →")
                    .font(DS.Font.sans(12, weight: .medium))
                    .foregroundStyle(DS.Color.ink3)
            }
            .buttonStyle(.plain)
        }
    }

    private var featureBadges: some View {
        HStack(spacing: 8) {
            badge(icon: .shield, text: isChinese ? "本地加密" : "Local-encrypted")
            badge(icon: .command, text: isChinese ? "快捷键优先" : "Keyboard-first")
            badge(icon: .inbox, text: isChinese ? "统一收件箱" : "Unified inbox")
            badge(icon: .sparkle, text: isChinese ? "AI 摘要" : "AI summary")
        }
    }

    private func badge(icon: DSIconName, text: String) -> some View {
        HStack(spacing: 5) {
            DSIcon(name: icon, size: 10)
                .foregroundStyle(DS.Color.ink3)
            Text(text)
                .font(DS.Font.sans(10.5, weight: .medium))
                .foregroundStyle(DS.Color.ink2)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            Capsule(style: .continuous).fill(DS.Color.surface2)
        )
        .overlay(
            Capsule(style: .continuous).stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
        )
    }

    private var isChinese: Bool { appState.language == .simplifiedChinese }
}
