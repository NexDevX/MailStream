import SwiftUI

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var recipient = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var localStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appState.strings.compose)
                .font(.system(size: 23, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            ComposeField(title: appState.strings.to, text: $recipient)
            ComposeField(title: appState.strings.subject, text: $subject)

            TextEditor(text: $messageBody)
                .font(.system(size: AppTheme.bodyFontSize))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )

            if let localStatusMessage {
                Text(localStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack {
                Button(appState.strings.cancel) {
                    dismiss()
                }
                .buttonStyle(.plain)

                Spacer()

                Button(appState.strings.saveDraft) {
                    dismiss()
                }
                .buttonStyle(.plain)

                Button(isSending ? appState.strings.syncingMailbox : appState.strings.send) {
                    Task {
                        await sendMessage()
                    }
                }
                .buttonStyle(MailStreaPrimaryButtonStyle())
                .frame(width: 148)
                .disabled(isSending || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 390)
        .background(AppTheme.panel)
    }

    private func sendMessage() async {
        guard isSending == false else {
            return
        }

        isSending = true
        localStatusMessage = nil
        defer { isSending = false }

        do {
            try await appState.sendMail(
                to: recipient,
                subject: subject,
                body: messageBody
            )
            dismiss()
        } catch {
            localStatusMessage = error.localizedDescription
        }
    }
}

private struct ComposeField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.panelBorder, lineWidth: 1)
                )
        }
    }
}
