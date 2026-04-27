import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            SearchBar()
            Divider().overlay(DS.Color.line)
            ListHeader()
            Divider().overlay(DS.Color.line)
            FilterChipsBar()
            if scopeChip != nil {
                Divider().overlay(DS.Color.line)
                scopeBar
            }
            Divider().overlay(DS.Color.line)
            list
        }
        .background(DS.Color.surface)
        // Trailing hairline removed — VerticalResizer in RootView draws it.
    }

    /// Active scope chip — derived from sidebar account/label scope.
    private var scopeChip: (label: String, tint: Color)? {
        if let id = appState.scopedAccountID,
           let acc = appState.accounts.first(where: { $0.id == id }) {
            return (
                "\(appState.language == .simplifiedChinese ? "账号：" : "Account: ")\(acc.displayName.isEmpty ? acc.emailAddress : acc.displayName)",
                ProviderPalette.color(for: acc.providerType)
            )
        }
        if let key = appState.scopedLabelKey {
            return ("\(appState.language == .simplifiedChinese ? "标签：" : "Label: ")\(key)", DS.Color.labelWork)
        }
        return nil
    }

    @ViewBuilder
    private var scopeBar: some View {
        if let chip = scopeChip {
            HStack(spacing: 8) {
                Circle().fill(chip.tint).frame(width: 7, height: 7)
                Text(chip.label)
                    .font(DS.Font.sans(11.5, weight: .medium))
                    .foregroundStyle(DS.Color.ink2)
                Spacer()
                Button {
                    withAnimation(DS.Motion.snap) { appState.clearScopes() }
                } label: {
                    HStack(spacing: 4) {
                        Text(appState.language == .simplifiedChinese ? "清除" : "Clear")
                            .font(DS.Font.sans(11, weight: .medium))
                        DSIcon(name: .close, size: 9)
                    }
                    .foregroundStyle(DS.Color.ink3)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .dsCard(cornerRadius: 5, fill: DS.Color.surface2)
                }
                .buttonStyle(.plain)
                .hoverLift()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(DS.Color.surface2)
        }
    }

    @ViewBuilder
    private var list: some View {
        if appState.filteredMessages.isEmpty {
            EmptyStateView(
                title: appState.strings.noMessagesTitle,
                systemImage: "tray",
                message: appState.strings.noMessagesMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.filteredMessages) { message in
                        MessageRow(
                            message: message,
                            isSelected: appState.selectedMessageID == message.id,
                            accountColor: color(for: message),
                            density: appState.listDensity
                        )
                        .onTapGesture { appState.selectMessage(message) }
                    }
                }
            }
        }
    }

    private func color(for message: MailMessage) -> Color {
        guard let id = message.accountID,
              let acc = appState.accounts.first(where: { $0.id == id })
        else {
            // Fall back to a deterministic mapping so the list isn't monochrome.
            let palette: [Color] = [DS.Color.pGmail, DS.Color.pOutlook, DS.Color.pQQ, DS.Color.pICloud, DS.Color.pCustom]
            return palette[abs(message.id.hashValue) % palette.count]
        }
        return ProviderPalette.color(for: acc.providerType)
    }
}

// MARK: - Search bar

private struct SearchBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            DSIcon(name: .search, size: 12.5)
                .foregroundStyle(DS.Color.ink4)
            TextField(appState.strings.searchMail, text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(12))
                .foregroundStyle(DS.Color.ink)
            Kbd(text: "⌘K")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .dsCard(cornerRadius: DS.Radius.md, fill: DS.Color.surface2)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - List header

private struct ListHeader: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Text(appState.strings.inbox)
                .font(DS.Font.sans(12.5, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Text("\(appState.filteredMessages.count)")
                .font(DS.Font.mono(10.5))
                .foregroundStyle(DS.Color.ink4)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DS.Color.surface3)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .compositingGroup()
            Spacer()
            HStack(spacing: 2) {
                HStack(spacing: 4) {
                    DSIcon(name: .arrowDown, size: 10)
                    Text(appState.strings.sortNewestFirst)
                        .font(DS.Font.sans(11))
                }
                .foregroundStyle(DS.Color.ink3)
                .padding(.horizontal, 8)
                .frame(height: 22)
                IconButton(icon: .filter)
                IconButton(icon: .refresh) {
                    Task { await appState.refreshMailbox() }
                }
                Menu {
                    Section(header: Text(appState.language == .simplifiedChinese ? "列表密度" : "Density")) {
                        ForEach(ListDensity.allCases) { density in
                            Button {
                                appState.listDensity = density
                            } label: {
                                if appState.listDensity == density {
                                    Label(densityLabel(density), systemImage: "checkmark")
                                } else {
                                    Text(densityLabel(density))
                                }
                            }
                        }
                    }
                } label: {
                    DSIcon(name: .more, size: 13)
                        .foregroundStyle(DS.Color.ink2)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 38)
    }

    private func densityLabel(_ density: ListDensity) -> String {
        let zh = appState.language == .simplifiedChinese
        switch density {
        case .compact:     return zh ? "紧凑" : "Compact"
        case .cozy:        return zh ? "常规" : "Cozy"
        case .comfortable: return zh ? "宽松" : "Comfortable"
        }
    }
}

// MARK: - Filter chips

private struct FilterChipsBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InboxFilterChip.allCases) { chip in
                FilterChipView(
                    label: label(for: chip),
                    count: appState.chipCount(chip),
                    icon: icon(for: chip),
                    isSelected: appState.selectedFilterChip == chip
                ) {
                    appState.selectedFilterChip = chip
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func label(for chip: InboxFilterChip) -> String {
        switch chip {
        case .all:      return appState.strings.chipAll
        case .unread:   return appState.strings.chipUnread
        case .priority: return appState.strings.chipPriority
        case .attach:   return appState.strings.chipAttach
        case .mentions: return appState.strings.chipMentions
        }
    }

    private func icon(for chip: InboxFilterChip) -> DSIconName? {
        switch chip {
        case .priority: return .flame
        case .attach:   return .paperclip
        default:        return nil
        }
    }
}

// MARK: - Row

struct MessageRow: View {
    let message: MailMessage
    let isSelected: Bool
    let accountColor: Color
    let density: ListDensity

    @State private var isHovered = false

    /// Treat priority as a surrogate for the "unread" visual weight until the
    /// model carries an explicit `isUnread` field.
    private var isUnread: Bool { message.isPriority }

    var body: some View {
        Group {
            switch density {
            case .compact:     compactBody
            case .cozy:        cozyBody
            case .comfortable: comfortableBody
            }
        }
        .frame(height: density.rowHeight)
        .background(Rectangle().fill(background))
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(DS.Color.accent)
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    // MARK: – Compact (single line)

    private var compactBody: some View {
        HStack(spacing: 8) {
            unreadDot
            Avatar(
                initials: message.senderInitials,
                size: 18,
                tint: AvatarTint.neutral(for: message.senderName),
                providerColor: accountColor
            )
            Text(message.senderName)
                .font(DS.Font.sans(12, weight: isUnread ? .semibold : .medium))
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            Text(message.subject)
                .font(DS.Font.sans(12, weight: isUnread ? .semibold : .regular))
                .foregroundStyle(DS.Color.ink2)
                .lineLimit(1)
                .layoutPriority(2)
            Text(message.preview)
                .font(DS.Font.sans(11.5))
                .foregroundStyle(DS.Color.ink4)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if message.attachments.isEmpty == false {
                DSIcon(name: .paperclip, size: 9)
                    .foregroundStyle(DS.Color.ink4)
            }
            Text(message.timestampLabel)
                .font(DS.Font.mono(10.5, weight: isUnread ? .semibold : .medium))
                .foregroundStyle(isUnread ? DS.Color.ink2 : DS.Color.ink4)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }

    // MARK: – Cozy (default — two effective lines but flat)

    private var cozyBody: some View {
        HStack(spacing: 10) {
            unreadDot
            Avatar(
                initials: message.senderInitials,
                size: 28,
                tint: AvatarTint.neutral(for: message.senderName),
                providerColor: accountColor
            )
            Text(message.senderName)
                .font(DS.Font.sans(12.5, weight: isUnread ? .bold : .medium))
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)
            HStack(spacing: 6) {
                if isUnread {
                    DSIcon(name: .pin, size: 11)
                        .foregroundStyle(DS.Color.amber)
                }
                Text(message.subject)
                    .font(DS.Font.sans(12.5, weight: isUnread ? .semibold : .medium))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text("— \(message.preview)")
                    .font(DS.Font.sans(12))
                    .foregroundStyle(DS.Color.ink3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if message.tag.isEmpty == false {
                LabelPill(text: localizedTag(message.tag))
            }
            Text(message.timestampLabel)
                .font(DS.Font.mono(11, weight: isUnread ? .semibold : .medium))
                .foregroundStyle(isUnread ? DS.Color.ink2 : DS.Color.ink4)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
    }

    // MARK: – Comfortable (full vertical stack)

    private var comfortableBody: some View {
        HStack(alignment: .top, spacing: 10) {
            unreadDot
                .padding(.top, 14)
            Avatar(
                initials: message.senderInitials,
                size: 34,
                tint: AvatarTint.neutral(for: message.senderName),
                providerColor: accountColor
            )
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.senderName)
                        .font(DS.Font.sans(13, weight: isUnread ? .bold : .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if message.attachments.isEmpty == false {
                        DSIcon(name: .paperclip, size: 10)
                            .foregroundStyle(DS.Color.ink4)
                    }
                    Text(message.timestampLabel)
                        .font(DS.Font.mono(11, weight: isUnread ? .semibold : .medium))
                        .foregroundStyle(isUnread ? DS.Color.ink2 : DS.Color.ink4)
                }
                Text(message.subject)
                    .font(DS.Font.sans(12.5, weight: isUnread ? .semibold : .medium))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(message.preview)
                        .font(DS.Font.sans(11.5))
                        .foregroundStyle(DS.Color.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if message.tag.isEmpty == false {
                        LabelPill(text: localizedTag(message.tag))
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Helpers

    private var unreadDot: some View {
        ZStack {
            if isUnread {
                Circle()
                    .fill(DS.Color.accent)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(DS.Color.accentGlow, lineWidth: 2).scaleEffect(2))
            }
        }
        .frame(width: 8)
    }

    private var background: Color {
        if isSelected { return DS.Color.selected }
        if isHovered { return DS.Color.hover }
        return DS.Color.surface
    }

    private func localizedTag(_ tag: String) -> String {
        switch tag.uppercased() {
        case "DESIGN": return "团队"
        case "DEV":    return "工作"
        case "ADMIN":  return "团队"
        case "DRAFT":  return "草稿"
        case "SENT":   return "已发送"
        case "SYSTEM": return "系统"
        default:       return tag
        }
    }
}

// MARK: - Label pill

struct LabelPill: View {
    let text: String
    var tint: Color = DS.Color.labelWork

    var body: some View {
        Text(text)
            .font(DS.Font.sans(10, weight: .semibold))
            .tracking(0.1)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .compositingGroup()
    }
}
