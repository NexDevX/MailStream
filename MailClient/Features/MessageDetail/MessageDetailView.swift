import SwiftUI

struct MessageDetailView: View {
    let message: MailMessage?

    var body: some View {
        Group {
            if let message {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.subject)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("\(message.senderName) <\(message.senderEmail)>")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    MessageWebView(html: message.bodyHTML)
                }
                .padding(20)
            } else {
                EmptyStateView(
                    title: "Select a Message",
                    systemImage: "envelope.open",
                    message: "Choose a mail item from the list to inspect its details."
                )
            }
        }
        .navigationTitle("Detail")
    }
}

#Preview {
    MessageDetailView(message: MailMessage.samples.first)
}
