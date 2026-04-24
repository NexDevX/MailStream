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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.Color.line)
            form
            Divider().overlay(DS.Color.line)
            footer
        }
        .frame(minWidth: 620, minHeight: 480)
        .background(DS.Color.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            DSIcon(name: .pencil, size: 13)
                .foregroundStyle(DS.Color.ink2)
            Text(appState.strings.compose)
                .font(DS.Font.sans(13, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            IconButton(icon: .close) { dismiss() }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(DS.Color.surface2)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            field(title: appState.strings.to, text: $recipient)
            Divider().overlay(DS.Color.line)
            field(title: appState.strings.subject, text: $subject)
            Divider().overlay(DS.Color.line)
            TextEditor(text: $messageBody)
                .font(DS.Font.sans(13.5))
                .foregroundStyle(DS.Color.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 260)
                .overlay(alignment: .topLeading) {
                    if messageBody.isEmpty {
                        Text("写点什么…")
                            .font(DS.Font.sans(13.5))
                            .foregroundStyle(DS.Color.ink4)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func field(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DS.Font.sans(11, weight: .semibold))
                .foregroundStyle(DS.Color.ink4)
                .tracking(0.4)
                .textCase(.uppercase)
                .frame(width: 58, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(DS.Font.sans(13))
                .foregroundStyle(DS.Color.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            IconButton(icon: .bold)
            IconButton(icon: .italic)
            IconButton(icon: .link)
            IconButton(icon: .list)
            IconButton(icon: .paperclip)

            if let localStatusMessage {
                Text(localStatusMessage)
                    .font(DS.Font.sans(11))
                    .foregroundStyle(DS.Color.red)
                    .padding(.leading, 8)
            }

            Spacer()

            Button(appState.strings.saveDraft) { dismiss() }
                .buttonStyle(.plain)
                .font(DS.Font.sans(12, weight: .medium))
                .foregroundStyle(DS.Color.ink3)
                .padding(.horizontal, 10)

            Kbd(text: "⌘")
            Kbd(text: "↵")

            Button {
                Task { await sendMessage() }
            } label: {
                HStack(spacing: 5) {
                    DSIcon(name: .send, size: 11)
                    Text(isSending ? appState.strings.syncingMailbox : appState.strings.send)
                        .font(DS.Font.sans(12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.accent.opacity(isDisabled ? 0.5 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(DS.Color.surface2)
    }

    private var isDisabled: Bool {
        isSending
            || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() async {
        guard isSending == false else { return }
        isSending = true
        localStatusMessage = nil
        defer { isSending = false }

        do {
            try await appState.sendMail(to: recipient, subject: subject, body: messageBody)
            dismiss()
        } catch {
            localStatusMessage = error.localizedDescription
        }
    }
}
