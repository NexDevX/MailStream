import SwiftUI

struct SettingsView: View {
    @AppStorage("mailclient.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("mailclient.desktop.badges") private var badgesEnabled = true
    @AppStorage("mailclient.links.external") private var openLinksExternally = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            Form {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Toggle("Show dock badge", isOn: $badgesEnabled)
                Toggle("Open links in browser", isOn: $openLinksExternally)
            }
            .formStyle(.grouped)
        }
        .padding(24)
        .frame(width: 480, height: 260)
        .background(AppTheme.panel)
    }
}
