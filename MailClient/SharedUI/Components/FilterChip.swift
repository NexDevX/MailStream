import SwiftUI

/// Compact pill used in the list filter bar (全部 / 未读 / 重要 / 附件 / @我).
struct FilterChipView: View {
    let label: String
    let count: Int
    var icon: DSIconName? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    DSIcon(name: icon, size: 10)
                }
                Text(label)
                    .font(DS.Font.sans(11, weight: .medium))
                Text("\(count)")
                    .font(DS.Font.mono(10))
                    .opacity(isSelected ? 0.78 : 0.58)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, icon == nil ? 9 : 8)
            .frame(height: 22)
            .foregroundStyle(isSelected ? Color.white : DS.Color.ink2)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? DS.Color.ink : (isHovered ? DS.Color.surface3 : DS.Color.surface))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.line, lineWidth: DS.Stroke.hairline)
            )
            .scaleEffect(isHovered && !isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.snap, value: isSelected)
        .animation(DS.Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
