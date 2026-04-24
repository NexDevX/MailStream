import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(DS.Color.ink4)
            Text(title)
                .font(DS.Font.sans(13, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Text(message)
                .font(DS.Font.sans(12))
                .foregroundStyle(DS.Color.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
    }
}
