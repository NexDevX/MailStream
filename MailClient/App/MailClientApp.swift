import SwiftUI

@main
struct MailClientApp: App {
    @StateObject private var appState: AppState
    /// Owns light/dark mode + the in-flight reveal animation. Lives at
    /// `App` scope so toggling never triggers a window re-creation, and
    /// so any view (sidebar, settings, command palette) can flip it via
    /// `@EnvironmentObject`.
    @StateObject private var themeController = ThemeController()

    init() {
        let container = AppContainer.live
        _appState = StateObject(wrappedValue: container.makeAppState())
    }

    var body: some Scene {
        WindowGroup(appState.strings.appName) {
            RootView()
                .environmentObject(appState)
                .environmentObject(themeController)
                // Floor low enough to fit a 13" laptop in split-screen
                // (left half ≈ 720pt). RootView collapses the sidebar
                // and switches to drilldown layout below 840pt.
                .frame(minWidth: 720, minHeight: 560)
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

                Button(appState.language == .simplifiedChinese ? "切换侧栏" : "Toggle Sidebar") {
                    appState.isSidebarVisible.toggle()
                }
                .keyboardShortcut("\\", modifiers: [.command, .control])

                Divider()

                Button(appState.strings.settings) {
                    appState.route = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
