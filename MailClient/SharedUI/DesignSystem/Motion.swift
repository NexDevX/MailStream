import SwiftUI

// MARK: - Motion tokens

extension DS {
    /// Centralized animation tokens — keeps motion consistent across surfaces.
    /// All values target the macOS feel: short, springy, never fussy.
    enum Motion {
        /// Snappy spring for selection indicators / matchedGeometryEffect.
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.78, blendDuration: 0)

        /// Soft spring for primary surface transitions (route / panel).
        static let surface = Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0)

        /// Quick ease for hover state, background tint, opacity flips.
        static let hover = Animation.easeOut(duration: 0.14)

        /// Press feedback — instant in, gentle out.
        static let press = Animation.spring(response: 0.22, dampingFraction: 0.6, blendDuration: 0)

        /// Long, lazy ambient loop (syncing dot, gradient drift).
        static let ambient = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)

        /// Generic content fade for chip changes etc.
        static let content = Animation.easeInOut(duration: 0.18)
    }
}

// MARK: - Hover scale modifier

/// Subtle hover lift used on tappable cells / chips. Pure visual — never moves layout.
struct HoverLift: ViewModifier {
    var pressed: CGFloat = 0.97
    var hovered: CGFloat = 1.02

    @State private var isHovered = false
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? pressed : (isHovered ? hovered : 1.0))
            .animation(DS.Motion.press, value: isPressed)
            .animation(DS.Motion.hover, value: isHovered)
            .onHover { isHovered = $0 }
            .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true })
    }
}

extension View {
    /// Apply the standard MailStream hover-lift effect.
    func hoverLift(pressed: CGFloat = 0.97, hovered: CGFloat = 1.02) -> some View {
        modifier(HoverLift(pressed: pressed, hovered: hovered))
    }
}

// MARK: - Pulse ring

/// Animated pulse ring used by status dots while syncing.
struct PulseRing: View {
    let color: Color
    var size: CGFloat = 8

    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.55), lineWidth: 1.5)
                .frame(width: size, height: size)
                .scaleEffect(animate ? 2.6 : 1)
                .opacity(animate ? 0 : 0.9)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: animate)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear { animate = true }
    }
}
