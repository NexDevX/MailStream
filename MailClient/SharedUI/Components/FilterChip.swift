import SwiftUI

/// Compact pill used in the list filter bar (全部 / 未读 / 重要 / 附件 / @我).
struct FilterChipView: View {
    let label: String
    let count: Int
    var icon: DSIconName? = nil
    let isSelected: Bool
    let action: () -> Void

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
            }
            .padding(.horizontal, icon == nil ? 9 : 8)
            .frame(height: 22)
            .foregroundStyle(isSelected ? Color.white : DS.Color.ink2)
            .background(
                Capsule(style: .continuous).fill(isSelected ? DS.Color.ink : DS.Color.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.line, lineWidth: DS.Stroke.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}
