import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 0.969, green: 0.961, blue: 0.949)
    static let panel = Color(red: 0.982, green: 0.976, blue: 0.965)
    static let panelBorder = Color.black.opacity(0.08)
    static let textPrimary = Color(red: 0.113, green: 0.113, blue: 0.105)
    static let textSecondary = Color(red: 0.392, green: 0.372, blue: 0.337)
    static let textTertiary = Color(red: 0.517, green: 0.494, blue: 0.455)
    static let accent = Color(red: 0.106, green: 0.106, blue: 0.094)
    static let selectedCard = Color.white

    static let sidebarWidth: CGFloat = 242
    static let listWidth: CGFloat = 344
    static let listMaxWidth: CGFloat = 392
    static let detailMinWidth: CGFloat = 720

    static let titleFontSize: CGFloat = 22
    static let sidebarTitleSize: CGFloat = 24
    static let sectionHeaderSize: CGFloat = 14
    static let bodyFontSize: CGFloat = 15
    static let captionSize: CGFloat = 12
}
