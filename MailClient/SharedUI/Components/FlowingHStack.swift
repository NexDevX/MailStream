import SwiftUI

/// Lightweight wrap-on-overflow horizontal stack for chip-style content.
///
/// Why not `HStack` + `Spacer`? HStack doesn't wrap; tall chip lists run off
/// the trailing edge.
/// Why not `LazyVGrid`? LazyVGrid forces a fixed column count; we want chips
/// to size to their content.
/// Why not `Layout` (custom)? Layout requires iOS 16+ / macOS 13+ and pulls
/// in proposal-resolution code we don't need for ≤ 30 chips.
///
/// This implementation uses a single `Layout` conformance — it's the
/// idiomatic SwiftUI way on macOS 14+. Constant time per child, no
/// preference-key gymnastics.
struct FlowingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lines: [CGFloat] = [0]
        var lineHeights: [CGFloat] = [0]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let last = lines.count - 1
            let projected = lines[last] + (lines[last] > 0 ? spacing : 0) + size.width
            if projected > maxWidth, lines[last] > 0 {
                lines.append(size.width)
                lineHeights.append(size.height)
            } else {
                lines[last] = projected
                lineHeights[last] = max(lineHeights[last], size.height)
            }
        }

        let height = lineHeights.reduce(0, +) + max(0, CGFloat(lineHeights.count - 1)) * lineSpacing
        let width  = lines.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            _ = maxWidth // silence unused
        }
    }
}
