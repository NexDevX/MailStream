import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            routed

            if appState.isShowingCommandPalette {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: appState.isShowingCommandPalette)
        .animation(.easeInOut(duration: 0.18), value: appState.route)
        .onAppear { syncRouteWithAccounts() }
        .onChange(of: appState.accounts) { syncRouteWithAccounts() }
        .onChange(of: appState.isShowingCompose) {
            if appState.isShowingCompose {
                appState.openCompose()
                appState.isShowingCompose = false
            }
        }
    }

    @ViewBuilder
    private var routed: some View {
        switch appState.route {
        case .mail:          mailLayout
        case .onboarding:    OnboardingView()
        case .accountWizard: AccountWizardView()
        case .settings:      SettingsView()
        case .search:        SearchView()
        case .compose:       ComposeTabsView()
        }
    }

    private var mailLayout: some View {
        GeometryReader { geometry in
            let layout = AppTheme.layout(for: geometry.size)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: layout.sidebarWidth)

                    MessageListView()
                        .frame(
                            minWidth: layout.listMinWidth,
                            idealWidth: layout.listIdealWidth,
                            maxWidth: layout.listMaxWidth
                        )

                    MessageDetailView(
                        message: appState.selectedMessage,
                        layout: layout
                    )
                    .frame(minWidth: layout.detailMinWidth, maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)

                StatusBarView()
            }
            .background(DS.Color.bg)
        }
    }

    private func syncRouteWithAccounts() {
        if appState.accounts.isEmpty, appState.route == .mail {
            appState.route = .onboarding
        }
    }
}
