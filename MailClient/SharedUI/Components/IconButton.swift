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
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            DSIcon(name: icon, size: size)
                .foregroundStyle(isHovered ? DS.Color.ink : tint)
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(background)
                )
                .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.06 : 1.0))
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.hover, value: isHovered)
        .animation(DS.Motion.press, value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var background: Color {
        if isActive { return DS.Color.surface3 }
        return isHovered ? DS.Color.hover : .clear
    }
}
