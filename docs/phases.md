# Phase Tracker

A running record of architectural work-in-flight, so we don't lose context
between sessions. Each phase has: scope, files touched, status, blockers.

## ✅ Phase 0 — UI scaffolding (DONE)

Design system, core 3-pane layout, onboarding, account wizard, settings,
compose tabs, search, command palette, animations, anti-aliasing pass,
interaction wiring, status banner.

## ✅ Phase 1 — Persistence foundation (DONE)

Files in `MailClient/Persistence/`:
- `SQLite.swift` — actor-wrapped sqlite3 (WAL + 128MB mmap + 8MB pages)
- `MailDatabase.swift` — single-connection owner + linear migrations
- `Schema/V1_Initial.swift` — accounts, folders, messages, attachments,
  sync_state, drafts, FTS5 + triggers
- `DAO/AccountDAO.swift`, `FolderDAO.swift`, `MessageDAO.swift` (incl.
  `HeaderUpsert` payload + FTS5 BM25 search)

Files in `MailClient/Services/Providers/`:
- `MailProviderAdapter.swift` — new protocol (header-first, UID-keyed,
  capability flags) + `RemoteFolder`, `RemoteHeader`, `RemoteBody`,
  `MailProviderAdapterRegistry`

Docs:
- `architecture.md` rewritten

**Build & tests green. Nothing wired into AppContainer yet — the new
layer co-exists with the existing in-memory repo.**

## ✅ Phase 2 — Wire the cache end-to-end (DONE)

Files added:
- `Persistence/MailStoreRepository.swift` — SQLite-backed `MailRepository`
  with in-memory snapshot caching, atomic batch writes, and lossy round-trip
  for legacy `MailMessage` (highlights/closing dropped on persist).
- `Persistence/MailStoreAccountRepository.swift` — thin wrapper over
  `AccountDAO`.

Files modified:
- `App/AppContainer.swift` — opens `MailDatabase` synchronously, builds
  the SQLite-backed repos, falls back to `:memory:` if Application Support
  is unreachable.
- `App/AppState.swift` — accepts an optional `database` and runs
  `database.prepare()` (migrations) at the top of `bootstrap()`.
- `Persistence/MailDatabase.swift` — split init into sync open + async
  `prepare()`.
- `Tests/PersistenceTests.swift` — 5 new tests: migration shape,
  account/message round-trip, FTS5 search, end-to-end repository.

Mail now persists across launches. SQLite is the source of truth; the old
`FileBackedMailRepository` is no longer used by the live container.

## 🟡 Phase 2 leftovers

- `MailStoreRepository.compose` puts every loaded message into
  `.allMail` until folderRole→sidebarItem inversion is wired. Sent items
  show up but aren't categorized. Easy follow-up.
- `AppState.messages` is still `[MailMessage]`. Phase 2.5 should swap to
  `[MailMessageSummary]` so list views don't carry body text in RAM.
- `FileBackedMailRepository.swift` and `FileBackedMailAccountRepository.swift`
  are now dead code — keep one release for emergency fallback then delete.

All five sub-steps shipped — see the DONE section above.

## 🔜 Phase 3 — Real provider adapters

Per-provider implementations of `MailProviderAdapter`:
- `QQMailAdapter` — wrap the existing IMAP code currently in
  `QQMailService.swift` (kept untouched in Phase 1 to avoid breakage)
- `GenericIMAPAdapter` — host/port/auth pluggable
- `GmailAdapter` — OAuth2 + Gmail REST API
- `OutlookAdapter` — MSAL + Microsoft Graph
- `ICloudAdapter` — IMAP with app-specific password

Once adapters exist, `MailSyncEngine.swift` (under `Services/`) coordinates
fetch → DAO writes → `AppState` notifies on `@Published` summaries.

## 🔜 Phase 4 — Adaptivity & energy

- Settings/Compose/Wizard fluid widths via GeometryReader (currently
  partial)
- `@ScaledMetric` on Retina/4K
- `NSBackgroundActivityScheduler` for idle sync
- `MailDatabase.evictBodies(olderThan: 7d)` triggered by app-idle event

## 🟡 Outstanding feedback (not yet addressed)

User-reported issues — order doesn't imply priority.

| # | Issue | Status | Where |
|---|-------|--------|-------|
| F1 | "Add account" click felt laggy | ✅ FIXED — connecting transition | `AccountWizardView.swift` |
| F2 | Body shows raw MIME headers | ✅ FIXED — proper MIME parser | `MIMEParser.swift` |
| F3 | Body not selectable | ✅ FIXED — `.textSelection(.enabled)` on subject/sender/body | `MessageDetailView.swift` |
| F4 | List/detail split ratio fixed | ✅ FIXED — drag handle + `@AppStorage` persistence | `Resizer.swift`, `RootView.swift` |
| F5 | Window adaptivity below 1040 px | ✅ FIXED — `minWidth` lowered to 720 × 560. Three breakpoints with auto-collapsing sidebar (1180–1480) and drilldown mode (< 840) where list and detail swap places with iOS-style back navigation. | `AppTheme.swift`, `RootView.swift`, `AdaptiveBars.swift`, `AppState.swift` |
| F12 | Scroll wheel over HTML body doesn't scroll the page | ✅ FIXED — `ScrollPassthroughWebView` subclass overrides `scrollWheel(with:)` to forward events up the responder chain instead of letting the internal NSScrollView consume them. | `HTMLMessageBodyView.swift` |
| F6 | Real MIME parser (multipart, charset, qp/base64) | ✅ FIXED — `MIMEParser` recursive walk + 7 unit tests | `MIMEParser.swift`, `QQMailService.swift` |
| F7 | Memory: messages stay in `@Published [MailMessage]` | ✅ FIXED — header/body split. `MailMessage` is header-only; `MailMessageBody` is loaded on selection through `MailMessageBodyStore` (LRU, capacity 64). Detail view shows skeleton during load. Reply/forward fetch on demand, fall back to preview on cache miss. | `MailMessage.swift`, `MailMessageBodyStore.swift`, `AppState.swift`, `MessageDetailView.swift`, `MailRepository.swift` |
| F9 | Mail persists across launches | ✅ FIXED — SQLite-backed repository | `MailStoreRepository.swift` |
| F8 | Attachments visible to user | ✅ FIXED — `MailAttachment` struct + clickable chips with file-type colored badges; `FlowingHStack` for wrap. Click triggers banner until IMAP lands. | `MailMessage.swift`, `MessageDetailView.swift`, `FlowingHStack.swift` |
| F10 | List pane min width too wide | ✅ FIXED — `listMinWidth` lowered to 280 / 300 / 320 across breakpoints; `listMaxWidth` raised to 520–700 so the user can drag substantially in either direction. | `AppTheme.swift` |
| F11 | Plain-text bodies look ugly vs QQ web client | ✅ FIXED — full HTML rendering via `WKWebView` wrapped in `HTMLMessageBodyView`. JavaScript disabled; remote images blocked behind a "Show images" privacy toggle. Dynamic content height via `document.body.scrollHeight`; links open in default browser. Plain-text fallback when no HTML part. | `HTMLMessageBodyView.swift`, `MessageDetailView.swift`, `MailMessage.swift` |
