import SwiftUI

@main
struct MailClientApp: App {
    private let container: AppContainer
    @StateObject private var appState: AppState

    init() {
        let container = AppContainer.live
        self.container = container
        _appState = StateObject(wrappedValue: container.makeAppState())
    }

    var body: some Scene {
        WindowGroup("MailStrea") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1380, minHeight: 900)
                .task {
                    await container.syncService.bootstrap()
                    appState.reloadMessages()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Mailbox") {
                Button("Refresh") {
                    Task {
                        await container.syncService.refreshAll()
                        await MainActor.run {
                            appState.reloadMessages()
                        }
                    }
                }
                .keyboardShortcut("r")

                Button("Compose") {
                    appState.isShowingCompose = true
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
        }
    }
}
