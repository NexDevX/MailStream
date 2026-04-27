import SwiftUI
import AppKit

/// Vertical drag handle used between the message list and the reading pane.
///
/// Behavior:
/// - 4 px wide hit area, 1 px hairline visible.
/// - Cursor flips to `resizeLeftRight` on hover.
/// - Live drag updates `width` (via the binding) so the layout responds in
///   real time. The parent clamps the value within `[min, max]`.
/// - Double-click resets to a sensible default.
///
/// We intentionally don't repaint anything per-frame outside the bound width
/// so the splitter is energy-cheap.
struct VerticalResizer: View {
    @Binding var width: CGFloat
    let bounds: ClosedRange<CGFloat>
    let defaultWidth: CGFloat
    var onChanged: ((CGFloat) -> Void)? = nil

    @State private var isHovered = false
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(isHovered ? DS.Color.accent.opacity(0.5) : DS.Color.line)
                    .frame(width: isHovered ? 2 : 1)
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil { dragStart = width }
                        let next = (dragStart ?? width) + value.translation.width
                        let clamped = min(max(next, bounds.lowerBound), bounds.upperBound)
                        width = clamped
                        onChanged?(clamped)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                width = defaultWidth
                onChanged?(defaultWidth)
            }
            .accessibilityLabel("Resize divider")
    }
}
