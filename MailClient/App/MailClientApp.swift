import SwiftUI

@main
struct MailClientApp: App {
    @StateObject private var appState: AppState

    init() {
        let container = AppContainer.live
        _appState = StateObject(wrappedValue: container.makeAppState())
    }

    var body: some Scene {
        WindowGroup(appState.strings.appName) {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 940, minHeight: 640)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu(appState.strings.mailboxMenu) {
                Button(appState.strings.refresh) {
                    Task {
                        await appState.refreshMailbox()
                    }
                }
                .keyboardShortcut("r")

                Button(appState.strings.compose) {
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
