import SwiftUI

/// Full-screen search surface with facet panel, filter chip bar, and grouped results.
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var queryFocused: Bool
    @State private var query = ""
    @State private var selectedAccountID: MailAccount.ID?
    @State private var selectedRange: TimeRange = .anytime
    @State private var hasAttachment = false

    enum TimeRange: String, CaseIterable, Identifiable {
        case anytime, today, week, month
        var id: String { rawValue }
        func label(zh: Bool) -> String {
            switch (self, zh) {
            case (.anytime, true):  return "任何时间"
            case (.anytime, false): return "Anytime"
            case (.today, true):    return "今天"
            case (.today, false):   return "Today"
            case (.week, true):     return "本周"
            case (.week, false):    return "This week"
            case (.month, true):    return "本月"
            case (.month, false):   return "This month"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.Color.line)
            filterBar
            Divider().overlay(DS.Color.line)
            HStack(spacing: 0) {
                facets
                Divider().overlay(DS.Color.line)
                results
            }
        }
        .background(DS.Color.bg)
        .onAppear { queryFocused = true }
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                appState.route = .mail
            } label: {
                DSIcon(name: .chevronLeft, size: 12)
                    .foregroundStyle(DS.Color.ink3)
                    .frame(width: 28, height: 28)
                    .dsCard(cornerRadius: 5)
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                DSIcon(name: .search, size: 14)
                    .foregroundStyle(DS.Color.ink3)
                TextField(isChinese ? "搜索所有账号的邮件…" : "Search across all accounts…", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.Font.sans(14))
                    .focused($queryFocused)
                if query.isEmpty == false {
                    Button { query = "" } label: {
                        DSIcon(name: .close, size: 10).foregroundStyle(DS.Color.ink4)
                    }
                    .buttonStyle(.plain)
                }
                Kbd(text: "esc")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .dsCard(cornerRadius: 8)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(filteredMessages.count) \(isChinese ? "条结果" : "results")")
                    .font(DS.Font.sans(11.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink2)
                Text(isChinese ? "本地索引 · 0.04s" : "Local · 0.04s")
                    .font(DS.Font.mono(10))
                    .foregroundStyle(DS.Color.ink4)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(DS.Color.surface2)
    }

    // MARK: – Filter chip bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    Button(isChinese ? "全部账号" : "All accounts") { selectedAccountID = nil }
                    Divider()
                    ForEach(appState.accounts) { acc in
                        Button(acc.displayName.isEmpty ? acc.emailAddress : acc.displayName) {
                            selectedAccountID = acc.id
                        }
                    }
                } label: {
                    chip(label: isChinese ? "账号" : "Account",
                         value: selectedAccountID.flatMap { id in appState.accounts.first { $0.id == id }?.displayName } ?? (isChinese ? "全部" : "All"))
                }
                .menuStyle(.borderlessButton).fixedSize()

                Menu {
                    ForEach(TimeRange.allCases) { range in
                        Button(range.label(zh: isChinese)) { selectedRange = range }
                    }
                } label: {
                    chip(label: isChinese ? "时间" : "Time",
                         value: selectedRange.label(zh: isChinese))
                }
                .menuStyle(.borderlessButton).fixedSize()

                Toggle(isOn: $hasAttachment) {
                    chip(label: isChinese ? "含附件" : "Attachment",
                         value: hasAttachment ? (isChinese ? "是" : "Yes") : (isChinese ? "否" : "No"))
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)

                Menu {
                    // mock options
                    Button("发件人包含…") { appState.snoozeBannerMessage = "发件人筛选（mock）" }
                    Button("时间范围…") { appState.snoozeBannerMessage = "时间筛选（mock）" }
                    Button("标签…") { appState.snoozeBannerMessage = "标签筛选（mock）" }
                } label: {
                    HStack(spacing: 4) {
                        DSIcon(name: .plus, size: 10).foregroundStyle(DS.Color.ink3)
                        Text(isChinese ? "添加筛选" : "Add filter")
                            .font(DS.Font.sans(11.5, weight: .medium))
                            .foregroundStyle(DS.Color.ink3)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule(style: .continuous).fill(DS.Color.surface))
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(DS.Color.line, style: StrokeStyle(lineWidth: DS.Stroke.hairline, dash: [3, 3]))
                    )
                    .compositingGroup()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .background(DS.Color.surface)
    }

    private func chip(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(DS.Font.sans(10.5, weight: .semibold))
                .foregroundStyle(DS.Color.ink4)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(DS.Font.sans(11.5, weight: .medium))
                .foregroundStyle(DS.Color.ink2)
            DSIcon(name: .chevronDown, size: 9).foregroundStyle(DS.Color.ink4)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule(style: .continuous).fill(DS.Color.surface2))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.line, lineWidth: DS.Stroke.hairline))
        .compositingGroup()
    }

    // MARK: – Facets

    private var facets: some View {
        VStack(alignment: .leading, spacing: 16) {
            facetGroup(title: isChinese ? "按账号" : "By account") {
                ForEach(appState.accounts) { acc in
                    facetRow(
                        color: ProviderPalette.color(for: acc.providerType),
                        label: acc.displayName.isEmpty ? acc.emailAddress : acc.displayName,
                        count: appState.messages.filter { $0.accountID == acc.id }.count,
                        isActive: selectedAccountID == acc.id
                    ) {
                        selectedAccountID = selectedAccountID == acc.id ? nil : acc.id
                    }
                }
                if appState.accounts.isEmpty {
                    Text(isChinese ? "暂无账号" : "No accounts")
                        .font(DS.Font.sans(11)).foregroundStyle(DS.Color.ink4)
                }
            }

            facetGroup(title: isChinese ? "按时间" : "By time") {
                ForEach(TimeRange.allCases) { range in
                    facetRow(
                        color: DS.Color.ink4,
                        label: range.label(zh: isChinese),
                        count: nil,
                        isActive: selectedRange == range
                    ) {
                        selectedRange = range
                    }
                }
            }

            facetGroup(title: isChinese ? "按类型" : "By kind") {
                facetRow(color: DS.Color.amber, label: isChinese ? "重要" : "Priority",
                         count: appState.messages.filter(\.isPriority).count, isActive: false) {}
                facetRow(color: DS.Color.green, label: isChinese ? "含附件" : "With attachment",
                         count: nil, isActive: hasAttachment) { hasAttachment.toggle() }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(width: 220)
        .background(DS.Color.surface2)
    }

    @ViewBuilder
    private func facetGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(DS.Font.sans(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DS.Color.ink4)
                .padding(.bottom, 2)
            content()
        }
    }

    private func facetRow(color: Color, label: String, count: Int?, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(DS.Font.sans(12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? DS.Color.ink : DS.Color.ink2)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(DS.Font.mono(10))
                        .foregroundStyle(DS.Color.ink4)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? DS.Color.selected : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Results

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if filteredMessages.isEmpty {
                    EmptyStateView(
                        title: query.isEmpty
                            ? (isChinese ? "开始搜索" : "Start a search")
                            : (isChinese ? "没有匹配结果" : "No matches"),
                        systemImage: "magnifyingglass",
                        message: query.isEmpty
                            ? (isChinese ? "试试搜索发件人、主题或关键词。" : "Try a sender, subject, or keyword.")
                            : (isChinese ? "尝试调整筛选条件或换个关键词。" : "Try different filters or keywords.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    resultGroup(title: isChinese ? "今天" : "Today",
                                items: filteredMessages.prefix(3))
                    if filteredMessages.count > 3 {
                        resultGroup(title: isChinese ? "本周" : "This week",
                                    items: filteredMessages.dropFirst(3))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func resultGroup<S: Sequence>(title: String, items: S) -> some View where S.Element == MailMessage {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Font.sans(10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(DS.Color.ink4)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                let array = Array(items)
                ForEach(Array(array.enumerated()), id: \.element.id) { idx, message in
                    resultRow(message)
                    if idx < array.count - 1 {
                        Divider().overlay(DS.Color.line)
                    }
                }
            }
            .dsCard()
        }
    }

    private func resultRow(_ message: MailMessage) -> some View {
        Button {
            appState.selectedMessageID = message.id
            appState.route = .mail
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Avatar(
                    initials: message.senderInitials,
                    size: 30,
                    providerColor: providerColor(for: message)
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(message.senderName)
                            .font(DS.Font.sans(12.5, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                        Text(message.tag)
                            .font(DS.Font.sans(10, weight: .semibold))
                            .foregroundStyle(DS.Color.ink3)
                        Spacer()
                        Text(message.timestampLabel)
                            .font(DS.Font.mono(10.5))
                            .foregroundStyle(DS.Color.ink4)
                    }
                    Text(highlight(message.subject))
                        .font(DS.Font.sans(13, weight: .medium))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Text(highlight(message.preview))
                        .font(DS.Font.sans(11.5))
                        .foregroundStyle(DS.Color.ink3)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func highlight(_ string: String) -> AttributedString {
        var attr = AttributedString(string)
        guard query.isEmpty == false else { return attr }
        let lower = string.lowercased()
        let needle = query.lowercased()
        var searchStart = lower.startIndex
        while let range = lower.range(of: needle, range: searchStart..<lower.endIndex) {
            if let attrRange = Range<AttributedString.Index>(range, in: attr) {
                attr[attrRange].backgroundColor = DS.Color.amberSoft
                attr[attrRange].foregroundColor = DS.Color.ink
            }
            searchStart = range.upperBound
        }
        return attr
    }

    private func providerColor(for message: MailMessage) -> Color {
        if let id = message.accountID, let acc = appState.accounts.first(where: { $0.id == id }) {
            return ProviderPalette.color(for: acc.providerType)
        }
        return DS.Color.ink4
    }

    // MARK: – Filtering

    private var filteredMessages: [MailMessage] {
        appState.messages.filter { msg in
            if let id = selectedAccountID, msg.accountID != id { return false }
            if query.isEmpty == false {
                let q = query.lowercased()
                let blob = (msg.subject + msg.preview + msg.senderName + msg.tag).lowercased()
                if blob.contains(q) == false { return false }
            }
            if hasAttachment, msg.preview.lowercased().contains("attach") == false,
               msg.preview.contains("附件") == false { return false }
            return true
        }
    }

    private var isChinese: Bool { appState.language == .simplifiedChinese }
}
