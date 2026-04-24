import SwiftUI

/// Circular initials avatar with optional provider indicator at bottom-right.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 28
    var tint: Color? = nil
    var providerColor: Color? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(tint ?? DS.Color.surface3)
                .overlay(
                    Text(initials.prefix(2))
                        .font(DS.Font.sans(size * 0.38, weight: .bold))
                        .foregroundStyle(DS.Color.ink2)
                )
                .overlay(
                    Circle().stroke(DS.Color.line, lineWidth: 0.5)
                )
                .frame(width: size, height: size)

            if let providerColor {
                Circle()
                    .fill(providerColor)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .overlay(Circle().stroke(DS.Color.surface, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }
        }
    }
}

enum AvatarTint {
    static func neutral(for seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.86, green: 0.89, blue: 0.95),
            Color(red: 0.89, green: 0.86, blue: 0.94),
            Color(red: 0.88, green: 0.91, blue: 0.95),
            Color(red: 0.94, green: 0.87, blue: 0.87),
            Color(red: 0.87, green: 0.91, blue: 0.88),
            Color(red: 0.89, green: 0.90, blue: 0.92)
        ]
        let index = abs(seed.hashValue) % palette.count
        return palette[index]
    }
}
