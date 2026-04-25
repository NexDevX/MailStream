import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            routed
                .id(appState.route)
                .transition(routeTransition)

            if appState.isShowingCommandPalette {
                CommandPaletteView()
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
                                .combined(with: .move(edge: .top))
                    )
            }
        }
        .animation(DS.Motion.surface, value: appState.isShowingCommandPalette)
        .animation(DS.Motion.surface, value: appState.route)
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

    private var routeTransition: AnyTransition {
        switch appState.route {
        case .onboarding, .accountWizard:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                removal: .opacity
            )
        case .settings, .search:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            )
        case .compose:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .move(edge: .bottom))
            )
        case .mail:
            return .opacity
        }
    }

    private func syncRouteWithAccounts() {
        if appState.accounts.isEmpty, appState.route == .mail {
            appState.route = .onboarding
        }
    }
}
