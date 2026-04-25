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
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu(appState.strings.mailboxMenu) {
                Button(appState.strings.refresh) {
                    Task { await appState.refreshMailbox() }
                }
                .keyboardShortcut("r")

                Button(appState.strings.compose) {
                    appState.isShowingCompose = true
                }
                .keyboardShortcut("n")

                Button(appState.strings.commandPalette) {
                    appState.isShowingCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button(appState.strings.settings) {
                    appState.route = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
