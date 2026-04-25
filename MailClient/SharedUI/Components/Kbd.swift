import SwiftUI

/// Keyboard hint badge — matches `.kbd` from the design system.
struct Kbd: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Font.mono(10, weight: .medium))
            .foregroundStyle(DS.Color.ink3)
            .padding(.horizontal, 5)
            .frame(minWidth: 14, minHeight: 16)
            .dsCard(cornerRadius: 3, stroke: DS.Color.lineStrong)
    }
}
