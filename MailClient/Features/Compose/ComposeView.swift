import SwiftUI

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var recipient = ""
    @State private var subject = ""
    @State private var messageBody = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Compose")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            ComposeField(title: "To", text: $recipient)
            ComposeField(title: "Subject", text: $subject)

            TextEditor(text: $messageBody)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Save Draft") {
                    dismiss()
                }
                .buttonStyle(MailStreaPrimaryButtonStyle())
                .frame(width: 180)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
        .background(AppTheme.panel)
    }
}

private struct ComposeField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )
        }
    }
}
