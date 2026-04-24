import SwiftUI

/// Compact square glyph button used across toolbars.
struct IconButton: View {
    let icon: DSIconName
    var size: CGFloat = 13
    var side: CGFloat = 24
    var tint: Color = DS.Color.ink2
    var isActive: Bool = false
    var action: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            DSIcon(name: icon, size: size)
                .foregroundStyle(tint)
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isActive { return DS.Color.surface3 }
        return isHovered ? DS.Color.hover : .clear
    }
}
