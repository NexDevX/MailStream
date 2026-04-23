import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(Mailbox.allCases, selection: $appState.selectedMailbox) { mailbox in
            Label(mailbox.rawValue, systemImage: mailbox.systemImageName)
                .tag(mailbox)
        }
        .navigationTitle("Mailboxes")
        .listStyle(.sidebar)
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState())
}
