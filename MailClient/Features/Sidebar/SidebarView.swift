import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            composeButton
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 6)

            navSection
                .padding(.top, 4)

            accountsSection
            labelsSection

            Spacer(minLength: 0)

            userFooter
        }
        .background(DS.Color.surface2)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.Color.line).frame(width: 1)
        }
    }

    // MARK: – Brand

    private var brandHeader: some View {
        Menu {
            // Workspace switcher (mock — single workspace today).
            Button {
                appState.clearScopes()
                appState.selectedSidebarItem = .allMail
            } label: { Label("MailStream · 个人", systemImage: "checkmark") }
            Divider()
            Button("管理工作区…")  { appState.route = .settings }
            Button("帮助与快捷键…") { appState.route = .settings }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(white: 0.13), Color(white: 0.05)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("M")
                        .font(DS.Font.mono(11, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("MailStream")
                    .font(DS.Font.sans(13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                DSIcon(name: .chevronDown, size: 12)
                    .foregroundStyle(DS.Color.ink4)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var composeButton: some View {
        Button { appState.openCompose() } label: {
            HStack(spacing: 7) {
                DSIcon(name: .pencil, size: 12)
                    .foregroundStyle(DS.Color.ink2)
                Text(appState.strings.compose)
                    .font(DS.Font.sans(12, weight: .medium))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Kbd(text: "C")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .dsCard(cornerRadius: DS.Radius.md, stroke: DS.Color.lineStrong)
        }
        .buttonStyle(.plain)
        .hoverLift(pressed: 0.98, hovered: 1.01)
    }

    // MARK: – Nav

    @Namespace private var navNamespace

    private var navSection: some View {
        VStack(spacing: 1) {
            ForEach(SidebarItem.allCases) { item in
                NavRow(
                    icon: item.designIcon,
                    label: item.title(in: appState.language),
                    count: navCount(for: item),
                    isSelected: appState.selectedSidebarItem == item && appState.route == .mail,
                    namespace: navNamespace
                ) {
                    withAnimation(DS.Motion.snap) {
                        if item == .drafts, appState.composeDrafts.isEmpty == false {
                            appState.route = .compose
                        } else {
                            appState.selectedSidebarItem = item
                            appState.route = .mail
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func navCount(for item: SidebarItem) -> Int {
        switch item {
        case .drafts:  return appState.composeDrafts.count
        case .priority: return appState.messages.filter(\.isPriority).count
        default:       return appState.messages.filter { $0.sidebarItem == item }.count
        }
    }

    // MARK: – Accounts

    private var accountsSection: some View {
        Section(title: appState.strings.accountsSection, onPlus: {
            appState.route = .accountWizard
        }) {
            VStack(spacing: 1) {
                if appState.accounts.isEmpty {
                    EmptyHint(text: appState.strings.noAccountsTitle)
                } else {
                    // "All accounts" reset row when a scope is active.
                    if appState.scopedAccountID != nil {
                        AccountRow(
                            name: appState.language == .simplifiedChinese ? "全部账号" : "All accounts",
                            unread: 0,
                            color: DS.Color.ink4,
                            isDisabled: false,
                            isSelected: false
                        ) {
                            withAnimation(DS.Motion.snap) {
                                appState.scopeToAccount(nil)
                            }
                        }
                    }
                    ForEach(appState.accounts) { acc in
                        let unread = appState.messages.filter { $0.accountID == acc.id }.count
                        AccountRow(
                            name: acc.displayName.isEmpty ? acc.emailAddress : acc.displayName,
                            unread: unread,
                            color: ProviderPalette.color(for: acc.providerType),
                            isDisabled: appState.isAccountDisabled(acc),
                            isSelected: appState.scopedAccountID == acc.id
                        ) {
                            withAnimation(DS.Motion.snap) {
                                appState.scopeToAccount(acc.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: – Labels

    private var labelsSection: some View {
        Section(title: appState.strings.labelsSection, onPlus: {
            // mock — would open a "new label" sheet. Surfaces a banner.
            appState.mailboxStatusMessage = appState.language == .simplifiedChinese
                ? "新建标签：暂未实现，敬请期待"
                : "New label — coming soon"
        }) {
            VStack(spacing: 1) {
                if appState.scopedLabelKey != nil {
                    LabelRow(
                        name: appState.language == .simplifiedChinese ? "全部标签" : "All labels",
                        color: DS.Color.ink4,
                        isSelected: false
                    ) {
                        withAnimation(DS.Motion.snap) {
                            appState.scopeToLabel(nil)
                        }
                    }
                }
                ForEach(Self.labels) { label in
                    LabelRow(
                        name: label.name,
                        color: label.color,
                        isSelected: appState.scopedLabelKey == label.name
                    ) {
                        withAnimation(DS.Motion.snap) {
                            appState.scopeToLabel(label.name)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    struct LabelToken: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    static let labels: [LabelToken] = [
        .init(id: "work",    name: "工作", color: DS.Color.labelWork),
        .init(id: "receipt", name: "收据", color: DS.Color.labelReceipt),
        .init(id: "travel",  name: "差旅", color: DS.Color.labelTravel),
        .init(id: "team",    name: "团队", color: DS.Color.labelTeam),
        .init(id: "client",  name: "客户", color: DS.Color.labelClient)
    ]

    // MARK: – User footer

    private var userFooter: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(LinearGradient(
                        colors: [DS.Color.accentSoft, DS.Color.selectedStr],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 24, height: 24)
                Text("JC")
                    .font(DS.Font.sans(10, weight: .bold))
                    .foregroundStyle(DS.Color.accentInk)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Joey Chen")
                    .font(DS.Font.sans(11.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                HStack(spacing: 4) {
                    Circle().fill(DS.Color.green).frame(width: 4, height: 4)
                    Text("\(appState.accounts.count) \(appState.strings.accountsSection)")
                        .font(DS.Font.sans(10))
                        .foregroundStyle(DS.Color.ink4)
                }
            }
            Spacer(minLength: 0)
            Button {
                appState.route = .settings
            } label: {
                DSIcon(name: .settings, size: 13)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(DS.Color.surface2)
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.line).frame(height: 1)
                }
        )
    }
}

// MARK: - Sub views

private struct Section<Content: View>: View {
    let title: String
    var onPlus: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var plusHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(DS.Font.sans(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(DS.Color.ink4)
                Spacer()
                if let onPlus {
                    Button(action: onPlus) {
                        DSIcon(name: .plus, size: 11)
                            .foregroundStyle(plusHovered ? DS.Color.ink2 : DS.Color.ink4)
                            .frame(width: 16, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(plusHovered ? DS.Color.hover : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(DS.Motion.hover) { plusHovered = hovering }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 5)

            content()
        }
    }
}

private struct NavRow: View {
    let icon: DSIconName
    let label: String
    let count: Int
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DSIcon(name: icon, size: 13)
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.ink3)
                    .scaleEffect(isSelected ? 1.05 : 1)
                Text(label)
                    .font(DS.Font.sans(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.ink2)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.mono(10, weight: .semibold))
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.ink4)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DS.Color.selected)
                            .matchedGeometryEffect(id: "navSelection", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DS.Color.hover)
                    }
                }
            )
            .compositingGroup()
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(DS.Color.accent)
                        .frame(width: 2, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                        .offset(x: -6)
                        .matchedGeometryEffect(id: "navAccentBar", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.snap, value: isSelected)
        .onHover { hovering in
            withAnimation(DS.Motion.hover) { isHovered = hovering }
        }
    }
}

private struct AccountRow: View {
    let name: String
    let unread: Int
    let color: Color
    var isDisabled: Bool = false
    var isSelected: Bool = false
    var action: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ProviderDot(color: color, size: 7, haloed: !isDisabled)
                    .opacity(isDisabled ? 0.4 : 1)
                Text(name)
                    .font(DS.Font.sans(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.ink2)
                    .strikethrough(isDisabled, color: DS.Color.ink4)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if unread > 0, !isDisabled {
                    Text("\(unread)")
                        .font(DS.Font.mono(10))
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.ink4)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? DS.Color.selected : (isHovered ? DS.Color.hover : .clear))
            )
            .compositingGroup()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DS.Motion.hover) { isHovered = hovering }
        }
    }
}

private struct LabelRow: View {
    let name: String
    let color: Color
    var isSelected: Bool = false
    var action: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(DS.Font.sans(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.ink2)
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? DS.Color.selected : (isHovered ? DS.Color.hover : .clear))
            )
            .compositingGroup()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(DS.Motion.hover) { isHovered = hovering }
        }
    }
}

private struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Font.sans(11))
            .foregroundStyle(DS.Color.ink4)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

// MARK: - Design icon mapping

private extension SidebarItem {
    var designIcon: DSIconName {
        switch self {
        case .allMail:  return .inbox
        case .priority: return .flame
        case .drafts:   return .draft
        case .sent:     return .send
        case .trash:    return .trash
        }
    }
}
