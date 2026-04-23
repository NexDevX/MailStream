import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 0.948, green: 0.955, blue: 0.963)
    static let panel = Color(red: 0.984, green: 0.986, blue: 0.989)
    static let panelElevated = Color.white
    static let panelMuted = Color(red: 0.936, green: 0.945, blue: 0.955)
    static let panelBorder = Color(red: 0.67, green: 0.70, blue: 0.74).opacity(0.32)
    static let chrome = Color(red: 0.204, green: 0.200, blue: 0.190)
    static let chromeText = Color(red: 0.926, green: 0.926, blue: 0.910)
    static let chromeMuted = Color.white.opacity(0.58)
    static let chromeField = Color.white.opacity(0.08)
    static let chromeFieldBorder = Color.white.opacity(0.12)
    static let textPrimary = Color(red: 0.086, green: 0.094, blue: 0.106)
    static let textSecondary = Color(red: 0.355, green: 0.382, blue: 0.421)
    static let textTertiary = Color(red: 0.545, green: 0.574, blue: 0.615)
    static let accent = Color(red: 0.098, green: 0.129, blue: 0.176)
    static let focusAccent = Color(red: 0.176, green: 0.333, blue: 0.682)
    static let priorityAccent = Color(red: 0.818, green: 0.447, blue: 0.114)
    static let destructive = Color(red: 0.700, green: 0.160, blue: 0.130)
    static let success = Color(red: 0.082, green: 0.508, blue: 0.337)
    static let successBright = Color(red: 0.050, green: 0.740, blue: 0.460)
    static let successSurface = Color(red: 0.875, green: 0.969, blue: 0.929)
    static let info = Color(red: 0.150, green: 0.450, blue: 0.950)
    static let selectedCard = Color(red: 0.965, green: 0.976, blue: 0.992)
    static let softIconSurface = Color(red: 0.935, green: 0.939, blue: 0.984)

    static let providerQQ = Color(red: 0.120, green: 0.330, blue: 0.910)
    static let providerGmail = Color(red: 0.960, green: 0.270, blue: 0.240)
    static let providerOutlook = Color(red: 0.170, green: 0.390, blue: 0.880)
    static let providerICloud = Color(red: 0.290, green: 0.350, blue: 0.440)
    static let providerCustom = Color(red: 0.580, green: 0.380, blue: 0.820)

    static let titleFontSize: CGFloat = 18
    static let sidebarTitleSize: CGFloat = 20
    static let sectionHeaderSize: CGFloat = 12
    static let bodyFontSize: CGFloat = 14
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
        if size.width < 980 {
            return LayoutMetrics(
                sidebarWidth: 188,
                listMinWidth: 270,
                listIdealWidth: 292,
                listMaxWidth: 316,
                detailMinWidth: 430,
                detailContentWidth: 620,
                detailHorizontalPadding: 24
            )
        }

        if size.width < 1280 {
            return LayoutMetrics(
                sidebarWidth: 210,
                listMinWidth: 300,
                listIdealWidth: 326,
                listMaxWidth: 358,
                detailMinWidth: 540,
                detailContentWidth: 700,
                detailHorizontalPadding: 34
            )
        }

        return LayoutMetrics(
            sidebarWidth: 224,
            listMinWidth: 324,
            listIdealWidth: 352,
            listMaxWidth: 404,
            detailMinWidth: 620,
            detailContentWidth: 760,
            detailHorizontalPadding: 42
        )
    }
}
