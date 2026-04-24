import SwiftUI

/// Primary filled button — used for Send, Save & Connect, etc.
struct MailStreaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.sans(12, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: DS.Stroke.hairline)
            )
    }
}

/// Secondary outlined button — Compose sidebar CTA, inline actions.
struct MailStreaSecondaryButtonStyle: ButtonStyle {
    var accessory: AnyView? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.sans(12, weight: .medium))
            .foregroundStyle(DS.Color.ink)
            .padding(.vertical, 0)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.lineStrong, lineWidth: DS.Stroke.hairline)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
