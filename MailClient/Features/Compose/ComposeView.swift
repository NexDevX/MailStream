import SwiftUI

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var to = ""
    @State private var subject = ""
    @State private var body = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compose")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("To", text: $to)
            TextField("Subject", text: $subject)

            TextEditor(text: $body)
                .frame(minHeight: 240)
                .overlay(alignment: .topLeading) {
                    if body.isEmpty {
                        Text("Write your message...")
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save Draft") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}

#Preview {
    ComposeView()
}
