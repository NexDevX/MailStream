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
    }

    static func layout(for size: CGSize) -> LayoutMetrics {
        if size.width < 1040 {
            return LayoutMetrics(
                sidebarWidth: 200,
                listMinWidth: 360,
                listIdealWidth: 400,
                listMaxWidth: 440,
                detailMinWidth: 460,
                detailContentWidth: 640,
                detailHorizontalPadding: 28
            )
        }
        if size.width < 1360 {
            return LayoutMetrics(
                sidebarWidth: 216,
                listMinWidth: 420,
                listIdealWidth: 460,
                listMaxWidth: 500,
                detailMinWidth: 540,
                detailContentWidth: 680,
                detailHorizontalPadding: 36
            )
        }
        return LayoutMetrics(
            sidebarWidth: 232,
            listMinWidth: 460,
            listIdealWidth: 480,
            listMaxWidth: 520,
            detailMinWidth: 620,
            detailContentWidth: 680,
            detailHorizontalPadding: 44
        )
    }
}
