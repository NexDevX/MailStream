import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    /// User-resizable list pane width. Persisted via @AppStorage so the
    /// user's preference survives relaunches.
    @AppStorage("mailclient.layout.listWidth") private var listWidth: Double = 460
    /// Mirror of the Settings → 通用 → 角标 toggle. Drives the dock
    /// tile badge: when on we render the unread count, when off we
    /// blank it. The toggle is the single source of truth — flipping
    /// it from any view immediately reflects on the dock.
    @AppStorage("mailclient.desktop.badges") private var badgesEnabled = true

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

            // Snooze / mock-feature toast — sits above all routes, dismisses
            // after 3.5s. Driven entirely by appState.snoozeBannerMessage so
            // any feature can surface a banner.
            if let banner = appState.snoozeBannerMessage {
                VStack {
                    StatusBanner(
                        message: banner,
                        icon: .clock,
                        tint: DS.Color.accent,
                        onDismiss: { appState.snoozeBannerMessage = nil }
                    )
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: banner) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        await MainActor.run {
                            if appState.snoozeBannerMessage == banner {
                                appState.snoozeBannerMessage = nil
                            }
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .animation(DS.Motion.surface, value: appState.snoozeBannerMessage)
        .animation(DS.Motion.surface, value: appState.isShowingCommandPalette)
        .animation(DS.Motion.surface, value: appState.route)
        .onAppear {
            syncRouteWithAccounts()
            updateDockBadge()
        }
        .onChange(of: appState.accounts) { syncRouteWithAccounts() }
        .onChange(of: appState.messages) { updateDockBadge() }
        .onChange(of: badgesEnabled) { updateDockBadge() }
        .onChange(of: appState.isShowingCompose) {
            if appState.isShowingCompose {
                appState.openCompose()
                appState.isShowingCompose = false
            }
        }
    }

    /// Push the unread count onto `NSApp.dockTile.badgeLabel`, or
    /// clear it when the user has the toggle off (or there's nothing
    /// to show). `unreadCount` is currently a UI-layer heuristic
    /// (`max(1, allMessages/3)`) — once the DAO surfaces real
    /// `flags_seen == 0` counts on `MailMessage`, the same wiring
    /// reads through. Setter must run on the main actor; `onChange`
    /// already gives us that guarantee inside SwiftUI.
    private func updateDockBadge() {
        let dock = NSApp.dockTile
        guard badgesEnabled else {
            if dock.badgeLabel != nil { dock.badgeLabel = nil }
            return
        }
        let count = appState.unreadCount
        let label: String? = count > 0 ? String(count) : nil
        if dock.badgeLabel != label {
            dock.badgeLabel = label
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
                if layout.prefersDrilldown {
                    drilldownPane(layout: layout, size: geometry.size)
                } else {
                    threePane(layout: layout, size: geometry.size)
                }
                StatusBarView()
            }
            .background(DS.Color.bg)
            // When the window crosses a breakpoint that hides drilldown,
            // make sure we don't get stuck on the detail pane with no
            // way back to the list.
            .onChange(of: layout.prefersDrilldown) {
                if layout.prefersDrilldown == false {
                    appState.isShowingDetailOverList = false
                }
            }
        }
    }

    /// Wide / medium regime: sidebar (optional) + list + resizer + detail.
    @ViewBuilder
    private func threePane(layout: AppTheme.LayoutMetrics, size: CGSize) -> some View {
        // The sidebar is visible when the user has it open AND the
        // breakpoint allows it (≥ 1180 always shows; 840–1180 lets the
        // user toggle).
        let sidebarVisible = layout.sidebarAutoCollapses
            ? appState.isSidebarVisible
            : true
        let sidebarTrack = sidebarVisible ? layout.sidebarWidth : 0

        let listMin: CGFloat = layout.listMinWidth
        let listMax: CGFloat = max(listMin + 40, size.width - sidebarTrack - layout.detailMinWidth)
        let clampedWidth = min(max(CGFloat(listWidth), listMin), listMax)
        let bindable = Binding<CGFloat>(
            get: { clampedWidth },
            set: { listWidth = Double($0) }
        )

        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: layout.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                if layout.sidebarAutoCollapses {
                    SidebarToggleBar(isVisible: $appState.isSidebarVisible)
                }
                MessageListView()
            }
            .frame(width: clampedWidth)

            VerticalResizer(
                width: bindable,
                bounds: listMin...listMax,
                defaultWidth: layout.listIdealWidth
            )

            MessageDetailView(
                message: appState.selectedMessage,
                layout: layout
            )
            .frame(minWidth: layout.detailMinWidth, maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
        .animation(DS.Motion.surface, value: sidebarVisible)
    }

    /// Drilldown regime: list OR detail at full width, with a back button
    /// in the detail header to pop back to the list.
    @ViewBuilder
    private func drilldownPane(layout: AppTheme.LayoutMetrics, size: CGSize) -> some View {
        let showingDetail = appState.isShowingDetailOverList && appState.selectedMessage != nil

        ZStack {
            if showingDetail {
                VStack(spacing: 0) {
                    DrilldownBackBar()
                    MessageDetailView(
                        message: appState.selectedMessage,
                        layout: layout
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    DrilldownTopBar()
                    MessageListView()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Motion.surface, value: showingDetail)
        .onChange(of: appState.selectedMessageID) {
            // In drilldown, tapping a list row pushes us into the detail
            // pane. The back bar / Esc returns.
            if appState.selectedMessageID != nil, showingDetail == false {
                appState.isShowingDetailOverList = true
            }
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
        if appState.accounts.isEmpty,
           appState.route == .mail,
           appState.hasDismissedOnboarding == false {
            appState.route = .onboarding
        }
    }
}
