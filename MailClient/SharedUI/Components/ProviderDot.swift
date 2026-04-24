import SwiftUI

/// Provider accent dot used beside account names and avatars.
struct ProviderDot: View {
    let color: Color
    var size: CGFloat = 7
    var haloed: Bool = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(haloed ? color.opacity(0.18) : .clear, lineWidth: 2)
                    .scaleEffect(haloed ? 1.9 : 1)
            )
    }
}

enum ProviderPalette {
    static func color(for type: MailProviderType) -> Color {
        switch type {
        case .qq:            return DS.Color.pQQ
        case .gmail:         return DS.Color.pGmail
        case .outlook:       return DS.Color.pOutlook
        case .icloud:        return DS.Color.pICloud
        case .customIMAPSMTP: return DS.Color.pCustom
        }
    }
}
