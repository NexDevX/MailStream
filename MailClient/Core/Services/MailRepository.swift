import Foundation

/// Storage-facing contract for mail.
///
/// Two planes — kept separate so callers must opt in to body IO:
///
/// - **Header plane** (`loadMessages` / `saveMessages` / `appendMessage`):
///   cheap. Always called by AppState on cold start and after sync.
///
/// - **Body plane** (`loadBody` / `storeBody`): expensive. Only the detail
///   view touches it, mediated by `MailMessageBodyStore`. Cache eviction
///   lives one level up; the repository only persists.
///
/// This split is what makes the steady-state RAM footprint bounded.
protocol MailRepository: Sendable {
    // Header / summary plane
    func loadMessages() async -> [MailMessage]
    func saveMessages(_ messages: [MailMessage]) async
    func appendMessage(_ message: MailMessage) async

    // Body plane
    func loadBody(messageID: UUID) async -> MailMessageBody?
    func storeBody(messageID: UUID, body: MailMessageBody) async
}
