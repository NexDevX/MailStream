import SwiftUI

struct SettingsView: View {
    @AppStorage("mailclient.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("mailclient.openLinksExternally") private var openLinksExternally = true

    var body: some View {
        Form {
            Toggle("Enable notifications", isOn: $notificationsEnabled)
            Toggle("Open links externally", isOn: $openLinksExternally)
        }
        .padding(20)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
}
