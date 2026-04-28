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

    // Folder + provider-shaped header plane (Phase 3 A6)
    //
    // The legacy `saveMessages` path keeps working for seed data and
    // local Sent mirrors, but the IMAP sync engine now writes through
    // `upsertRemoteHeaders` instead so real `remoteUID` /
    // `messageID` / `folderID` make it onto disk without going
    // through the lossy `MailMessage` round-trip.

    /// Persist the server-side folder list for an account. Idempotent
    /// per `(account, remoteID)`. Returns the persisted rows so the
    /// sync engine can address them by primary key when upserting
    /// headers.
    func upsertFolders(_ folders: [RemoteFolder], for account: MailAccount) async -> [MailFolder]

    /// Direct provider-shape header upsert. Bypasses `MailMessage` so
    /// `remoteUID`, `messageID`, `threadID`, and the real folder PK
    /// land on disk verbatim. Used by `MailSyncEngine.refreshAll`
    /// after `upsertFolders` has populated the folders table.
    func upsertRemoteHeaders(_ headers: [RemoteHeader], folder: MailFolder, account: MailAccount) async

    /// All persisted folders for an account, sorted by role then name.
    /// `[]` for in-memory test repositories.
    func listFolders(for accountID: UUID) async -> [MailFolder]

    /// Drop any in-memory derivations the repository keeps (header
    /// snapshots, summary caches, …). Used by debug "wipe local cache"
    /// after the SQLite tables have been re-created — without it the
    /// next `loadMessages()` would return the stale pre-wipe array.
    func invalidateCaches() async
}

extension MailRepository {
    /// Default — most repositories don't cache, so this is a no-op.
    /// `MailStoreRepository` overrides to drop its `headerSnapshot`.
    func invalidateCaches() async {}

    /// Defaults — in-memory / preview repositories don't model
    /// folders at all. Production `MailStoreRepository` overrides
    /// these to actually write SQLite rows.
    func upsertFolders(_ folders: [RemoteFolder], for account: MailAccount) async -> [MailFolder] { [] }
    func upsertRemoteHeaders(_ headers: [RemoteHeader], folder: MailFolder, account: MailAccount) async {}
    func listFolders(for accountID: UUID) async -> [MailFolder] { [] }
}
