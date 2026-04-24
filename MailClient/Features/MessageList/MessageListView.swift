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
            Divider().overlay(DS.Color.line)
            list
        }
        .background(DS.Color.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.Color.line).frame(width: 1)
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
                            accountColor: color(for: message)
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
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.line, lineWidth: DS.Stroke.hairline)
        )
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
                IconButton(icon: .more)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 38)
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

    @State private var isHovered = false

    /// Treat priority as a surrogate for the "unread" visual weight until the
    /// model carries an explicit `isUnread` field.
    private var isUnread: Bool { message.isPriority }

    var body: some View {
        HStack(spacing: 10) {
            // Unread indicator column
            ZStack {
                if isUnread {
                    Circle()
                        .fill(DS.Color.accent)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(DS.Color.accentGlow, lineWidth: 2).scaleEffect(2))
                }
            }
            .frame(width: 8)

            Avatar(
                initials: message.senderInitials,
                size: 28,
                tint: AvatarTint.neutral(for: message.senderName),
                providerColor: accountColor
            )

            // From
            Text(message.senderName)
                .font(DS.Font.sans(12.5, weight: isUnread ? .bold : .medium))
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            // Subject + preview
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

            // Labels
            if message.tag.isEmpty == false {
                LabelPill(text: localizedTag(message.tag))
            }

            // Time
            Text(message.timestampLabel)
                .font(DS.Font.mono(11, weight: isUnread ? .semibold : .medium))
                .foregroundStyle(isUnread ? DS.Color.ink2 : DS.Color.ink4)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 50)
        .background(
            Rectangle().fill(background)
        )
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

    private var background: Color {
        if isSelected { return DS.Color.selected }
        if isHovered { return DS.Color.hover }
        return DS.Color.surface
    }

    private func localizedTag(_ tag: String) -> String {
        // Designs use short Chinese chip strings; fall back to raw tag otherwise.
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
    }
}
