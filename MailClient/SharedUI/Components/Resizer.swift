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
    /// Fired on every drag tick. Use for cheap, transient updates.
    var onChanged: ((CGFloat) -> Void)? = nil
    /// Fired exactly once when the drag (or double-click reset)
    /// finishes. Use for expensive writes — `@AppStorage`,
    /// UserDefaults, server sync — so the heavy work doesn't run
    /// per-frame and feed back into the layout pipeline. Without
    /// this split a `@AppStorage`-bound width syncs to disk on
    /// every frame of the drag, which manifests as the entire
    /// HStack jittering as the layout pipeline races the IO.
    var onCommit: ((CGFloat) -> Void)? = nil

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
                    .onEnded { _ in
                        // Only commit if a real drag happened. Pure
                        // hover-and-release with no movement leaves
                        // dragStart nil; we skip the commit so we
                        // don't write the same value back.
                        if dragStart != nil {
                            onCommit?(width)
                        }
                        dragStart = nil
                    }
            )
            .onTapGesture(count: 2) {
                width = defaultWidth
                onChanged?(defaultWidth)
                onCommit?(defaultWidth)
            }
            .accessibilityLabel("Resize divider")
    }
}
