import SwiftUI

@main
struct MailClientApp: App {
    @StateObject private var appState = AppState()
    private let syncService = MailSyncService()

    var body: some Scene {
        WindowGroup("MailClient") {
            RootView()
                .environmentObject(appState)
                .task {
                    await syncService.bootstrap()
                }
        }
        .commands {
            CommandMenu("Mailbox") {
                Button("Refresh") {
                    Task {
                        await syncService.refreshAll()
                    }
                }
                .keyboardShortcut("r")

                Button("New Message") {
                    appState.isShowingCompose = true
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
