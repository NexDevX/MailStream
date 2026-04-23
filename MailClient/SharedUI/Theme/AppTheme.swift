import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 0.948, green: 0.955, blue: 0.963)
    static let panel = Color(red: 0.984, green: 0.986, blue: 0.989)
    static let panelElevated = Color.white
    static let panelMuted = Color(red: 0.936, green: 0.945, blue: 0.955)
    static let panelBorder = Color(red: 0.67, green: 0.70, blue: 0.74).opacity(0.32)
    static let textPrimary = Color(red: 0.086, green: 0.094, blue: 0.106)
    static let textSecondary = Color(red: 0.355, green: 0.382, blue: 0.421)
    static let textTertiary = Color(red: 0.545, green: 0.574, blue: 0.615)
    static let accent = Color(red: 0.098, green: 0.129, blue: 0.176)
    static let focusAccent = Color(red: 0.176, green: 0.333, blue: 0.682)
    static let priorityAccent = Color(red: 0.818, green: 0.447, blue: 0.114)
    static let selectedCard = Color(red: 0.965, green: 0.976, blue: 0.992)

    static let sidebarWidth: CGFloat = 224
    static let listWidth: CGFloat = 336
    static let listMaxWidth: CGFloat = 382
    static let detailMinWidth: CGFloat = 620

    static let titleFontSize: CGFloat = 18
    static let sidebarTitleSize: CGFloat = 20
    static let sectionHeaderSize: CGFloat = 12
    static let bodyFontSize: CGFloat = 14
    static let captionSize: CGFloat = 11
}
