import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }
}

struct AppStrings {
    let language: AppLanguage

    var appName: String { "MailStrea" }

    var workspaceTitle: String {
        switch language {
        case .english: return "Workspace"
        case .simplifiedChinese: return "工作区"
        }
    }

    var workspaceSubtitle: String {
        switch language {
        case .english: return "Editorial flow"
        case .simplifiedChinese: return "编辑流"
        }
    }

    var compose: String {
        switch language {
        case .english: return "Compose"
        case .simplifiedChinese: return "写邮件"
        }
    }

    var allMail: String {
        switch language {
        case .english: return "All Mail"
        case .simplifiedChinese: return "全部邮件"
        }
    }

    var priority: String {
        switch language {
        case .english: return "Priority"
        case .simplifiedChinese: return "优先"
        }
    }

    var drafts: String {
        switch language {
        case .english: return "Drafts"
        case .simplifiedChinese: return "草稿"
        }
    }

    var sent: String {
        switch language {
        case .english: return "Sent"
        case .simplifiedChinese: return "已发送"
        }
    }

    var trash: String {
        switch language {
        case .english: return "Trash"
        case .simplifiedChinese: return "废纸篓"
        }
    }

    var settings: String {
        switch language {
        case .english: return "Settings"
        case .simplifiedChinese: return "设置"
        }
    }

    var help: String {
        switch language {
        case .english: return "Help"
        case .simplifiedChinese: return "帮助"
        }
    }

    var inbox: String {
        switch language {
        case .english: return "Inbox"
        case .simplifiedChinese: return "收件箱"
        }
    }

    var focused: String {
        switch language {
        case .english: return "Focused"
        case .simplifiedChinese: return "重点"
        }
    }

    var archive: String {
        switch language {
        case .english: return "Archive"
        case .simplifiedChinese: return "归档"
        }
    }

    var unifiedInbox: String {
        switch language {
        case .english: return "Unified Inbox"
        case .simplifiedChinese: return "统一收件箱"
        }
    }

    var searchMail: String {
        switch language {
        case .english: return "Search mail"
        case .simplifiedChinese: return "搜索邮件"
        }
    }

    var searchAccounts: String {
        switch language {
        case .english: return "Search accounts"
        case .simplifiedChinese: return "搜索账户"
        }
    }

    var noMessagesTitle: String {
        switch language {
        case .english: return "No messages here"
        case .simplifiedChinese: return "这里没有邮件"
        }
    }

    var noMessagesMessage: String {
        switch language {
        case .english: return "Try another folder or clear the current search."
        case .simplifiedChinese: return "试试切换其他文件夹，或者清空当前搜索。"
        }
    }

    var mailboxMenu: String {
        switch language {
        case .english: return "Mailbox"
        case .simplifiedChinese: return "邮箱"
        }
    }

    var refresh: String {
        switch language {
        case .english: return "Refresh"
        case .simplifiedChinese: return "刷新"
        }
    }

    var selectMessageTitle: String {
        switch language {
        case .english: return "Select a message"
        case .simplifiedChinese: return "选择一封邮件"
        }
    }

    var selectMessageMessage: String {
        switch language {
        case .english: return "Pick an item from the list to open the reading surface."
        case .simplifiedChinese: return "从左侧列表选择一封邮件后，在这里查看正文。"
        }
    }

    var keyDecisions: String {
        switch language {
        case .english: return "Key Decisions:"
        case .simplifiedChinese: return "关键决定："
        }
    }

    var to: String {
        switch language {
        case .english: return "To"
        case .simplifiedChinese: return "收件人"
        }
    }

    var subject: String {
        switch language {
        case .english: return "Subject"
        case .simplifiedChinese: return "主题"
        }
    }

    var cancel: String {
        switch language {
        case .english: return "Cancel"
        case .simplifiedChinese: return "取消"
        }
    }

    var saveDraft: String {
        switch language {
        case .english: return "Save Draft"
        case .simplifiedChinese: return "保存草稿"
        }
    }

    var send: String {
        switch language {
        case .english: return "Send"
        case .simplifiedChinese: return "发送"
        }
    }

    var connectedAccounts: String {
        switch language {
        case .english: return "Connected Accounts"
        case .simplifiedChinese: return "已连接账户"
        }
    }

    var connectedAccountsSubtitle: String {
        switch language {
        case .english: return "Manage and monitor your integrated email sources in one place."
        case .simplifiedChinese: return "在一个面板里统一管理和监控接入的邮箱服务。"
        }
    }

    var addAccount: String {
        switch language {
        case .english: return "Add Account"
        case .simplifiedChinese: return "添加账户"
        }
    }

    var connectNewAccount: String {
        switch language {
        case .english: return "Connect New Account"
        case .simplifiedChinese: return "连接新账户"
        }
    }

    var accountSetup: String {
        switch language {
        case .english: return "Account Setup"
        case .simplifiedChinese: return "账户接入"
        }
    }

    var selectService: String {
        switch language {
        case .english: return "Select a service"
        case .simplifiedChinese: return "选择服务"
        }
    }

    var general: String {
        switch language {
        case .english: return "General"
        case .simplifiedChinese: return "通用"
        }
    }

    var account: String {
        switch language {
        case .english: return "Account"
        case .simplifiedChinese: return "账号"
        }
    }

    var qqMail: String {
        switch language {
        case .english: return "QQ Mail"
        case .simplifiedChinese: return "QQ 邮箱"
        }
    }

    var emailAddress: String {
        switch language {
        case .english: return "Email Address"
        case .simplifiedChinese: return "邮箱地址"
        }
    }

    var provider: String {
        switch language {
        case .english: return "Provider"
        case .simplifiedChinese: return "服务类型"
        }
    }

    var accountName: String {
        switch language {
        case .english: return "Account Name"
        case .simplifiedChinese: return "账户名称"
        }
    }

    var accountNamePlaceholder: String {
        switch language {
        case .english: return "Work Mail"
        case .simplifiedChinese: return "比如：工作邮箱"
        }
    }

    var accountSecret: String {
        switch language {
        case .english: return "App Password / Authorization Code"
        case .simplifiedChinese: return "应用专用密码 / 授权码"
        }
    }

    var authorizationCode: String {
        switch language {
        case .english: return "Authorization Code"
        case .simplifiedChinese: return "授权码"
        }
    }

    var qqMailHint: String {
        switch language {
        case .english:
            return "Enable POP3/SMTP in QQ Mail settings, then paste the generated authorization code here."
        case .simplifiedChinese:
            return "先在 QQ 邮箱网页端开启 POP3/SMTP 服务，再把生成的授权码填到这里。"
        }
    }

    var plannedProviderHint: String {
        switch language {
        case .english:
            return "The architecture is ready for Gmail, Outlook, iCloud, and custom IMAP/SMTP. QQ Mail is the first live connector."
        case .simplifiedChinese:
            return "当前架构已经为 Gmail、Outlook、iCloud 和自定义 IMAP/SMTP 预留扩展，QQ 邮箱是第一条可用连接器。"
        }
    }

    var saveAndConnect: String {
        switch language {
        case .english: return "Save and Connect"
        case .simplifiedChinese: return "保存并连接"
        }
    }

    var syncNow: String {
        switch language {
        case .english: return "Sync Now"
        case .simplifiedChinese: return "立即同步"
        }
    }

    var removeAccount: String {
        switch language {
        case .english: return "Remove Account"
        case .simplifiedChinese: return "移除账号"
        }
    }

    var accountNotConfigured: String {
        switch language {
        case .english: return "QQ Mail is not configured yet."
        case .simplifiedChinese: return "还没有配置可用邮箱账号。"
        }
    }

    var accountConnected: String {
        switch language {
        case .english: return "Mailbox account connected."
        case .simplifiedChinese: return "邮箱账号已连接。"
        }
    }

    var syncingMailbox: String {
        switch language {
        case .english: return "Syncing mailbox..."
        case .simplifiedChinese: return "正在同步邮箱..."
        }
    }

    var accountSaved: String {
        switch language {
        case .english: return "Account saved."
        case .simplifiedChinese: return "账号已保存。"
        }
    }

    var accountRemoved: String {
        switch language {
        case .english: return "Account removed."
        case .simplifiedChinese: return "账号已移除。"
        }
    }

    var sendSucceeded: String {
        switch language {
        case .english: return "Message sent."
        case .simplifiedChinese: return "邮件已发送。"
        }
    }

    var noAccountsTitle: String {
        switch language {
        case .english: return "No connected accounts yet"
        case .simplifiedChinese: return "还没有接入邮箱账户"
        }
    }

    var noAccountsMessage: String {
        switch language {
        case .english: return "Start with QQ Mail, then expand to more providers as the connector layer grows."
        case .simplifiedChinese: return "你可以先接入 QQ 邮箱，后面再沿着同一套连接器架构扩展更多服务。"
        }
    }

    var availableNow: String {
        switch language {
        case .english: return "Available now"
        case .simplifiedChinese: return "当前可用"
        }
    }

    var liveConnector: String {
        switch language {
        case .english: return "Live connector"
        case .simplifiedChinese: return "已实现连接器"
        }
    }

    var planned: String {
        switch language {
        case .english: return "Planned"
        case .simplifiedChinese: return "规划中"
        }
    }

    var comingSoon: String {
        switch language {
        case .english: return "Coming soon"
        case .simplifiedChinese: return "即将支持"
        }
    }

    var syncedJustNow: String {
        switch language {
        case .english: return "Synced just now"
        case .simplifiedChinese: return "刚刚同步"
        }
    }

    var neverSynced: String {
        switch language {
        case .english: return "Not synced yet"
        case .simplifiedChinese: return "尚未同步"
        }
    }

    var connectionError: String {
        switch language {
        case .english: return "Connection error"
        case .simplifiedChinese: return "连接异常"
        }
    }

    var languageSection: String {
        switch language {
        case .english: return "Language"
        case .simplifiedChinese: return "语言"
        }
    }

    var displayLanguage: String {
        switch language {
        case .english: return "Display Language"
        case .simplifiedChinese: return "界面语言"
        }
    }

    var enableNotifications: String {
        switch language {
        case .english: return "Enable notifications"
        case .simplifiedChinese: return "启用通知"
        }
    }

    var showDockBadge: String {
        switch language {
        case .english: return "Show dock badge"
        case .simplifiedChinese: return "显示 Dock 徽标"
        }
    }

    var openLinksInBrowser: String {
        switch language {
        case .english: return "Open links in browser"
        case .simplifiedChinese: return "在浏览器中打开链接"
        }
    }

    func selectionPosition(current: Int, total: Int) -> String {
        switch language {
        case .english:
            return "\(current) of \(total)"
        case .simplifiedChinese:
            return "\(current) / \(total)"
        }
    }

    func syncSucceeded(count: Int) -> String {
        switch language {
        case .english:
            return "Synced \(count) inbox messages."
        case .simplifiedChinese:
            return "已同步 \(count) 封收件箱邮件。"
        }
    }

    func syncedMinutesAgo(_ value: Int) -> String {
        switch language {
        case .english:
            return "Synced \(value)m ago"
        case .simplifiedChinese:
            return "\(value) 分钟前同步"
        }
    }

    func syncedHoursAgo(_ value: Int) -> String {
        switch language {
        case .english:
            return "Synced \(value)h ago"
        case .simplifiedChinese:
            return "\(value) 小时前同步"
        }
    }
}

extension SidebarItem {
    func title(in language: AppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .allMail: return strings.allMail
        case .priority: return strings.priority
        case .drafts: return strings.drafts
        case .sent: return strings.sent
        case .trash: return strings.trash
        }
    }
}

extension InboxFilter {
    func title(in language: AppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .inbox: return strings.inbox
        case .focused: return strings.focused
        case .archive: return strings.archive
        }
    }
}

extension MailProviderType {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .qq:
            return language == .simplifiedChinese ? "QQ 邮箱" : "QQ Mail"
        case .gmail:
            return "Gmail"
        case .outlook:
            return "Outlook"
        case .icloud:
            return "iCloud"
        case .customIMAPSMTP:
            return language == .simplifiedChinese ? "自定义 IMAP / SMTP" : "Custom IMAP / SMTP"
        }
    }

    var shortTag: String {
        switch self {
        case .qq:
            return "QQ"
        case .gmail:
            return "GMAIL"
        case .outlook:
            return "OUTLOOK"
        case .icloud:
            return "ICLOUD"
        case .customIMAPSMTP:
            return "IMAP"
        }
    }

    var systemImageName: String {
        switch self {
        case .qq:
            return "envelope.fill"
        case .gmail:
            return "at"
        case .outlook:
            return "briefcase.fill"
        case .icloud:
            return "icloud.fill"
        case .customIMAPSMTP:
            return "server.rack"
        }
    }
}
