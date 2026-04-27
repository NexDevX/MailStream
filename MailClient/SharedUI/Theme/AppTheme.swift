import SwiftUI

/// Compatibility shim — the canonical tokens live in `DS`.
/// Kept so that legacy call sites (e.g. Settings) keep compiling while the
/// codebase migrates to `DS.Color` / `DS.Font`.
enum AppTheme {
    static var canvas: Color         { DS.Color.bg }
    static var panel: Color          { DS.Color.surface2 }
    static var panelElevated: Color  { DS.Color.surface }
    static var panelMuted: Color     { DS.Color.surface3 }
    static var panelBorder: Color    { DS.Color.line }
    static var chrome: Color         { DS.Color.chromeTop }
    static var chromeText: Color     { DS.Color.ink }
    static var chromeMuted: Color    { DS.Color.ink3 }
    static var chromeField: Color    { DS.Color.surface3 }
    static var chromeFieldBorder: Color { DS.Color.line }
    static var textPrimary: Color    { DS.Color.ink }
    static var textSecondary: Color  { DS.Color.ink2 }
    static var textTertiary: Color   { DS.Color.ink3 }
    static var accent: Color         { DS.Color.accent }
    static var focusAccent: Color    { DS.Color.accent }
    static var priorityAccent: Color { DS.Color.amber }
    static var destructive: Color    { DS.Color.red }
    static var success: Color        { DS.Color.green }
    static var successBright: Color  { DS.Color.green }
    static var successSurface: Color { DS.Color.greenSoft }
    static var info: Color           { DS.Color.accent }
    static var selectedCard: Color   { DS.Color.selected }
    static var softIconSurface: Color { DS.Color.accentSoft }

    static var providerQQ: Color      { DS.Color.pQQ }
    static var providerGmail: Color   { DS.Color.pGmail }
    static var providerOutlook: Color { DS.Color.pOutlook }
    static var providerICloud: Color  { DS.Color.pICloud }
    static var providerCustom: Color  { DS.Color.pCustom }

    static let titleFontSize: CGFloat = 18
    static let sidebarTitleSize: CGFloat = 16
    static let sectionHeaderSize: CGFloat = 10
    static let bodyFontSize: CGFloat = 13
    static let captionSize: CGFloat = 11

    struct LayoutMetrics {
        let sidebarWidth: CGFloat
        let listMinWidth: CGFloat
        let listIdealWidth: CGFloat
        let listMaxWidth: CGFloat
        let detailMinWidth: CGFloat
        let detailContentWidth: CGFloat
        let detailHorizontalPadding: CGFloat
        /// Auto-collapse the sidebar below this width regardless of the
        /// user's manual toggle. False at the wide breakpoints.
        let sidebarAutoCollapses: Bool
        /// True when the window is narrow enough that list + detail
        /// can't both fit comfortably side by side. RootView switches to
        /// a drilldown (one-pane-at-a-time) layout in this regime.
        let prefersDrilldown: Bool
    }

    /// Three breakpoints, three regimes:
    ///
    /// - ≥ 1180  full three-pane layout
    /// - 840–1180 sidebar collapses to icon strip (or hidden), list+detail
    /// - < 840    drilldown — list OR detail, never both at once
    ///
    /// Below 720 we never go (window minWidth in MailClientApp).
    static func layout(for size: CGSize) -> LayoutMetrics {
        if size.width < 840 {
            // Drilldown regime — single pane fills the window. The
            // active pane width matters; min/ideal/max fold to the
            // available width.
            return LayoutMetrics(
                sidebarWidth: 0,                       // hidden
                listMinWidth: max(360, size.width - 8),
                listIdealWidth: size.width,
                listMaxWidth: .infinity,
                detailMinWidth: max(360, size.width - 8),
                detailContentWidth: max(420, size.width - 80),
                detailHorizontalPadding: 20,
                sidebarAutoCollapses: true,
                prefersDrilldown: true
            )
        }
        // Sidebar is always toggleable above the drilldown threshold —
        // users on big monitors still appreciate hiding chrome to focus
        // on the inbox. AppState.isSidebarVisible is the live source of
        // truth.
        if size.width < 1180 {
            return LayoutMetrics(
                sidebarWidth: 200,
                listMinWidth: 280,
                listIdealWidth: 360,
                listMaxWidth: 520,
                detailMinWidth: 440,
                detailContentWidth: 640,
                detailHorizontalPadding: 26,
                sidebarAutoCollapses: true,
                prefersDrilldown: false
            )
        }
        if size.width < 1480 {
            return LayoutMetrics(
                sidebarWidth: 216,
                listMinWidth: 300,
                listIdealWidth: 440,
                listMaxWidth: 600,
                detailMinWidth: 540,
                detailContentWidth: 680,
                detailHorizontalPadding: 36,
                sidebarAutoCollapses: true,
                prefersDrilldown: false
            )
        }
        return LayoutMetrics(
            sidebarWidth: 232,
            listMinWidth: 320,
            listIdealWidth: 460,
            listMaxWidth: 700,
            detailMinWidth: 620,
            detailContentWidth: 680,
            detailHorizontalPadding: 44,
            sidebarAutoCollapses: true,
            prefersDrilldown: false
        )
    }
}
