import SwiftUI

/// Lightweight floating banner used for transient status messages (snooze
/// confirmation, sync errors, mock-feature notices). Auto-dismisses after a
/// short interval. Designed to repaint at most once per show — no continuous
/// animation, no timers running while idle.
struct StatusBanner: View {
    let message: String
    var icon: DSIconName = .bell
    var tint: Color = DS.Color.accent
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            DSIcon(name: icon, size: 12)
                .foregroundStyle(tint)
            Text(message)
                .font(DS.Font.sans(12, weight: .medium))
                .foregroundStyle(DS.Color.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let onDismiss {
                Button(action: onDismiss) {
                    DSIcon(name: .close, size: 10)
                        .foregroundStyle(DS.Color.ink3)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 220, maxWidth: 480)
        .dsCard(
            cornerRadius: 10,
            fill: DS.Color.surface,
            stroke: DS.Color.lineStrong,
            shadowOpacity: 0.18,
            shadowRadius: 18,
            shadowY: 6
        )
    }
}
