# Development Log

> **Append-only.** Each entry has a date, what shipped, why, and what's
> next. Commits and chapters from a single working session are folded
> into one entry. For long-running architectural decisions also see
> [`roadmap.md`](./roadmap.md).

## How to add an entry

```
## YYYY-MM-DD — short title

### What landed
- Bullet list of changes, each ending with the file(s) touched.

### Why
One paragraph of context. Future-you reading this in six months wants
to know what triggered the change, not just what changed.

### Tests
- `xcodebuild ... build` — pass / fail
- `xcodebuild ... test` — N/N passed
- Manual smoke: <what was clicked through>

### Next
- Bullet of follow-ups.
```

---

## 2026-04-28 (later) — Live QQ smoke + flicker fix + MUTF-7 decoding

### What landed
- **`HTMLMessageBodyView.updateNSView` no-op short-circuit.** Previously
  every SwiftUI re-render of any ancestor (selection change, hover on
  a sibling button, our own height callback bouncing back into
  `@State contentHeight`) triggered `view.loadHTMLString(...)`, and
  WKWebView discards + repaints the document on every call —
  visually a white flash. Now the coordinator caches the last loaded
  HTML and we skip identical reloads. Also refresh
  `coordinator.parent` on each update so the height callback closure
  doesn't go stale.
  *Features/MessageDetail/HTMLMessageBodyView.swift*
- **IMAP-UTF7 (modified UTF-7) mailbox name decoding.** RFC 3501
  §5.1.3. QQ Mail returns Chinese folders like `&UXZO1mWHTvZZOQ-`
  (= `其他文件夹`); without decoding the sidebar shows mojibake and
  `roleForAttributes` can't match localized names. Implemented
  `IMAPResponseParser.decodeMailboxName(_:)` (handles `&-` ampersand
  escape, `,`→`/` base64 alphabet, padding-aware) + 5 unit tests.
  `GenericIMAPAdapter.listFolders` keeps `remoteID` in wire format
  (so SELECT byte-round-trips) and decodes only into `name` for UI +
  role guessing.
  *Services/Providers/IMAPResponseParser.swift,
   Services/Providers/GenericIMAPAdapter.swift,
   Tests/IMAPResponseParserTests.swift*
- **`IMAPLiveSmokeTests` — gated live smoke against a real QQ Mail
  account.** Reads `docs/password.TXT` (gitignored, two-line format:
  email + IMAP authorization code), opens an IMAP session through
  `QQMailAdapter`, exercises `validateConnection` → `listFolders` →
  `fetchHeaders(limit: 5)` → `fetchBody(latest)`. The whole suite is
  `.disabled(if:)` when the file isn't present, so CI / fresh
  checkouts skip silently. No credentials ever go into test output.
  Added `docs/password.TXT` and `docs/password.txt` to `.gitignore`.
  *Tests/IMAPLiveSmokeTests.swift, .gitignore*

### Why
The user's bug report hit two surfaces at once. The flicker is
trivially reproducible — any SwiftUI view rebuild reloads the
WebView and that's a white-flash + image re-fetch + height callback
storm. The MUTF-7 issue only surfaced because we ran live data
through the adapter for the first time; unit-test fixtures used pure
ASCII folder names so the parser passed without exercising the
encoding rules.

The smoke harness pays for itself in the next adapter — Gmail and
Outlook both have their own folder-name quirks, and a copy-paste
ready "give me a creds file, run one command" pattern means the next
provider integration is one-and-done.

### Tests
- `make generate && xcodebuild test` — **42/42** in 5 suites
- Live smoke against the user's QQ Mail account:
  - validateConnection: OK
  - listFolders: 7 folders, including `其他文件夹` and
    `其他文件夹/QQ邮件订阅` (decoded from MUTF-7)
  - fetchHeaders(Inbox, limit: 5): subjects in Chinese + English,
    UIDs sequential, INTERNALDATE present
  - fetchBody(latest): 2 KB plain text + 30 KB HTML, both decode to
    UTF-8 cleanly (Chinese characters intact)
- Manual flicker verification: needs the user's eyes — the bug is
  WKWebView-side and can only be confirmed with a running app.

### Next
- User to verify the flicker fix on the live app; if it persists,
  the next likely suspect is the height feedback loop (`@State
  contentHeight` updates → `.frame(height:)` change → `updateNSView`
  fires) which the no-op short-circuit should already break.
- Phase 3 A6 still pending: persist the (now correctly decoded)
  folder list, sidebar reads from the table, repository accepts
  `RemoteHeader` directly.

---

## 2026-04-28 — Phase 3 wire-up (workstream A4/A5)

### What landed
- **`MailSyncEngine`** replaces `MailSyncService`. Same actor surface
  (`refreshAll`, `send`, `loadAccounts`, …) so AppState's API stays
  intact — only the type name and the internals change. Per account
  the engine now: lists folders, picks the Inbox role, calls
  `adapter.fetchHeaders(cursor:limit:)` (50-row window), maps each
  `RemoteHeader` to a `MailMessage` with a **stable
  `synthesizeMessageID(accountID, remoteUID)` UUID** so re-syncs are
  idempotent and selection state survives a refresh, then queues the
  freshest 8 message bodies for prefetch. Bodies are stored via
  `repository.storeBody`; the existing `MailMessageBodyStore` LRU
  cache continues to mediate the detail view.
  *Core/Services/MailSyncEngine.swift, Tests/MailSyncEngineTests.swift*
- **`MailAccountService` → `MailProviderAdapterRegistry`.** Old
  `MailProviderRegistry` / `MailProvider` references removed. The
  service now hands out `any MailProviderAdapter`. `connectAccount`
  validates against the new adapter — same contract, different
  protocol.
  *Core/Services/MailAccountService.swift*
- **`AppContainer.live`** now registers
  `MailProviderAdapterRegistry([QQMailAdapter()])` and constructs a
  `MailSyncEngine`. The production graph is officially on IMAP — no
  more POP3 in the live path.
  *App/AppContainer.swift, App/AppState.swift, Tests/MailClientTests.swift*
- **Dead-code purge.** Deleted `MailProvider.swift` (the old
  protocol + registry), `QQMailProvider`, `SMTPMessageBuilder`,
  `RawInternetMessageParser`, `MailAddressParser`, and the private
  `Data.split(separator:)` extension — none of them had any caller
  after the rewire. The host file got renamed
  `Core/Services/QQMailService.swift` → `MailServiceShared.swift`
  with a header comment listing what's now inside (error type,
  TLS transport, formatter helpers).
- **`MailTimestampFormatter.displayValues(date:)`** — Date-typed
  sibling that avoids the round-trip through RFC 2822 string
  formatting when the caller already has a parsed `Date` (e.g. IMAP
  `INTERNALDATE`).
- **Stable `MailMessage.id`.** Implemented as a SHA-1 of
  `accountID || remoteUID.bigEndian` folded into a UUID. SHA-1 is fine
  here — the input space is tiny and the property we care about is
  determinism, not collision resistance. Built dependency-free in
  `MailSyncEngine.swift` so we don't pull `CryptoKit` into Core.

### Why
With the adapter shipped (A2/A3), nothing in the live graph called
into it. The point of A4/A5 is to flip the switch — make the adapter
the production path, retire the POP3 code, and lock the file/type
naming so future readers don't grep for `MailSyncService` and find a
ghost.

The stable-ID change is the subtle but important one. Previously
`MailMessage.id` was randomly generated each parse, so every refresh
rebuilt the header snapshot with new UUIDs and the body cache went
cold. Now the same `(account, UID)` always yields the same UUID — the
body cache hits, selection survives, and `MessageDAO.upsertHeader`'s
unique constraint on `(account, folder, remote_uid)` actually does
its job.

### Tests
- `make generate && xcodebuild build` — green
- `xcodebuild test` — **36/36** (8 new in `MailSyncEngineTests`,
  covering deterministic IDs, header field mapping, body line-ending
  normalization)
- Manual smoke: not run on a live QQ account — mailbox sync against
  the real server is the next session's first task.

### Next
- Phase 3 A6: persist real folder list per account; sidebar reads
  from `folders` table; `MailRepository` gets a "remote header upsert"
  path that doesn't lossy-convert through `MailMessage` so we can
  store true IMAP `remoteUID` / `messageID` / `threadID`.
- Phase 3 B: live smoke against a QQ Mail account; iron out edge
  cases (UTF-7 mailbox names, extremely large literals, IDLE for
  push).
- Phase 3 C: Gmail (XOAUTH2 + AppAuth) and Outlook (Graph) adapters.

---

## 2026-04-27 (later) — Phase 3 IMAP foundation (workstream A2/A3)

### What landed
- **IMAPResponseParser** — pure-Swift parsers for the IMAP4rev1 subset
  we need: tagged completion (`OK`/`NO`/`BAD`), `LIST` items
  (attributes / delimiter / name with quoted-string + NIL handling),
  `SELECT` summary (EXISTS / RECENT / UIDVALIDITY / UIDNEXT), and a
  FETCH atom walker that resolves literal placeholders to `Data`. Plus
  a small `roleForAttributes(_:name:)` mapping that handles both
  RFC 6154 special-use flags (`\Sent` / `\Drafts` / …) and localized
  QQ Mail folder names (`已发送` / `草稿箱` / `已删除` / `垃圾邮件`).
  *Services/Providers/IMAPResponseParser.swift, Tests/IMAPResponseParserTests.swift*
- **IMAPClient actor** — small client over the existing
  `SecureMailStreamClient` (NWConnection + TLS). Owns tag generation
  (`A0001`, `A0002`, …), per-command read loop until tagged completion,
  and — critically — IMAP literal handling. When a physical line ends
  with ` {N}`, we pull `N` raw bytes via the new
  `SecureMailStreamClient.readBytes(count:)` and substitute a sentinel
  `\u{1}<index>\u{1}` token in the assembled logical line so the
  parser can resolve it without re-scanning bytes that may contain
  CRLFs / parens / quotes. Commands: `LOGIN`, `LOGOUT`, `CAPABILITY`,
  `LIST`, `SELECT`/`EXAMINE`, `UID FETCH (UID FLAGS INTERNALDATE
  RFC822.SIZE BODY.PEEK[HEADER])`, `UID FETCH (UID FLAGS
  BODY.PEEK[])`, `UID STORE +FLAGS.SILENT|-FLAGS.SILENT`. 32 MB literal
  cap to refuse pathological responses.
  *Services/Providers/IMAPClient.swift, Core/Services/QQMailService.swift*
- **GenericIMAPAdapter** — first conforming type for the
  `MailProviderAdapter` protocol that's been sitting unused since
  Phase 1. Stateless / `Sendable`: every call opens a fresh IMAP
  connection, authenticates, runs, disconnects. (Connection pooling
  belongs to the future `MailSyncEngine`.) Header decoding feeds
  `BODY[HEADER]` through `MIMEParser` so RFC 2047 encoded-words and
  charset handling stay in one place; `INTERNALDATE` is preferred over
  `Date:` for `sentAt`. UIDVALIDITY mismatch invalidates the cursor
  and falls back to a window of size `limit` ending at `UIDNEXT-1`.
  Send goes via SMTP — same wire flow as the existing
  `QQMailService.send`, but localized inside the adapter so the legacy
  POP3 path can be deleted later without orphaning send.
  *Services/Providers/GenericIMAPAdapter.swift*
- **QQMailAdapter** — thin wrapper that pre-fills
  `IMAPProviderConfig` for `imap.qq.com:993` + `smtp.qq.com:465`.
  Capability set left empty until each (CONDSTORE / IDLE) is verified
  end-to-end against QQ.
  *Services/Providers/QQMailAdapter.swift*

### Why
`MailProviderAdapter` was added in Phase 1 (header-first / UID-keyed /
capability-flagged) but nothing implemented it; `MailProvider` (POP3-
shaped, "fetch all 12 most recent") still drove `MailSyncService`.
Phase 3 needs IMAP for multi-folder + Sent / Drafts / Junk and that
forced the question of which protocol the new code should target. We
went with `MailProviderAdapter` so the new sync engine in A4 can talk
to one shape — the legacy `QQMailService` keeps running until the
container is rewired in A5.

We also re-evaluated `dependencies.md`'s recommendation of
`swift-nio-imap`. Reading the current API confirmed it's a
`ChannelHandler` pair, not a high-level client — using it would mean
~800–1500 LOC of NIO bootstrap + tag/continuation coordination on top
of our actual adapter. For a single provider (QQ) the hand-rolled
client over `SecureMailStreamClient` is ~400 LOC and reuses the TLS
substrate we already use for POP3 / SMTP. Documented in
`dependencies.md` as a deferral, not a rejection — the picture changes
once we add Gmail (XOAUTH2) and Outlook (Graph), at which point NIOIMAP
might earn its keep.

### Tests
- `make generate && xcodebuild build` — green
- `xcodebuild test` — 28/28 (12 IMAP parser + 10 MIME parser + 6 base)
- Manual smoke: not yet — adapter lives outside the live composition
  root (`AppContainer` still wires `QQMailProvider` / POP3). Wiring
  is A5.

### Next
- Phase 3 A4: `MailSyncEngine` that drives the new adapter, owns
  cursor advancement, prioritizes Inbox over Archive.
- Phase 3 A5: switch `AppContainer` to register the adapter via
  `MailProviderAdapterRegistry`, retire `QQMailService`/`MailProvider`.
- Phase 3 A6: persist real folder list per account; sidebar reads
  from `folders` table instead of the static enum.

---

## 2026-04-27 — F10/F11/F12 + F5 + list density + flash fixes

### What landed
- **F10** — list pane min width lowered to 280/300/320 across breakpoints,
  max raised to 520/600/700; user can drag much more freely. *AppTheme.swift*
- **F11** — full HTML email rendering via `WKWebView`. Wrapped in
  `HTMLMessageBodyView` (NSViewRepresentable). JS disabled, links open
  in system browser, no `baseURL` set. Plain-text fallback when no HTML.
  *HTMLMessageBodyView.swift, MessageDetailView.swift, MailMessage.swift*
- **F12** — `ScrollPassthroughWebView` subclass overrides
  `scrollWheel(with:)` to forward to `nextResponder` so scroll over the
  HTML region works. *HTMLMessageBodyView.swift*
- **F5** — narrow window adaptation. minWidth dropped from 1040 to
  720×560. Three breakpoints: ≥1480 wide, 1180–1480 / 840–1180 sidebar
  toggleable, <840 drilldown (list ↔ detail with iOS-style back).
  *AppTheme.swift, RootView.swift, AdaptiveBars.swift, AppState.swift*
- **List density** — `ListDensity` enum (compact 32px / cozy 50px /
  comfortable 72px). Persisted to UserDefaults. Toggle from list header
  ⋯ menu. *AppState.swift, MessageListView.swift*
- **Sidebar always toggleable** at every non-drilldown breakpoint;
  ⌃⌘\ keyboard shortcut. *AppTheme.swift, MailClientApp.swift*
- **Flash fix** — removed `.animation(_, value: body)` and
  `.animation(_, value: isLoading)` on body view. Height changes go
  through immediately; only message-id transitions animate.
  *MessageDetailView.swift*
- **Default-on remote images** — `@AppStorage` flag defaults to true,
  removed the privacy notice strip. *MessageDetailView.swift*
- **HTML body width unleashed** — was capped at 860; now `.infinity`,
  HTML emails fill the detail pane and self-constrain via their own
  table widths. *MessageDetailView.swift*
- **Resize-feedback fix (earlier same day)** — replaced ResizeObserver
  with event-driven measurement (font ready, image load/error,
  setTimeout 80/200ms). Threshold raised to 4px Swift-side, 2px JS-side.
  Removed `body * { box-sizing: border-box }` and `td/div max-width:
  100% !important` which were both triggering width→height feedback.
  *HTMLMessageBodyView.swift*

### Why
Multiple compounding UX bugs surfaced from real testing with the user's
QQ inbox. The HTML rendering had three separate issues — internal
scroll, image-load flicker, height feedback — each masking the others.
The narrow-window work was previously deferred but became necessary as
the sidebar/list/detail proportions started limiting where the app
could be used (split-screen on 13" laptops).

### Tests
- `make generate && xcodebuild build` — green
- `xcodebuild test` — 17/17 passed
- Manual smoke: opened QQ marketing email, confirmed images render,
  scroll passes through HTML region, no flicker on resize, drilldown
  works at 720px.

### Next
- Phase 3 IMAP work (workstream A): pull `swift-nio-imap`, build
  `GenericIMAPAdapter`.

---

## 2026-04-26 — F8 attachments + F7 memory split

### What landed
- **F8** — `MailAttachment` struct with id/filename/mime/size/cachePath.
  Surfaced as proper chips (file-type colored badges, hover lift, click
  → banner placeholder until IMAP supports per-part fetch). New
  `FlowingHStack` Layout for multi-line wrap. Removed the `📎 line`
  emoji injection in the body parser. *MailMessage.swift,
  MessageDetailView.swift, FlowingHStack.swift*
- **F7** — header / body data model split. `MailMessage` is header-only;
  `MailMessageBody` (paragraphs / highlights / closing / htmlBody) is
  loaded on demand by `MailMessageBodyStore` (actor, LRU 64). AppState
  publishes `selectedBody` + `isLoadingSelectedBody`. Detail view shows
  skeleton during load. Reply / forward warm the cache before opening
  the draft. *MailMessage.swift, MailRepository.swift, MailStoreRepository.swift,
  InMemoryMailRepository.swift, MailMessageBodyStore.swift, AppState.swift,
  MessageDetailView.swift, SeedMailboxData.swift*
- **F6** — proper `MIMEParser` recursive walk; multipart/alternative
  picks text/plain over text/html, base64 + quoted-printable +
  GB2312/UTF-8 decode, RFC 2047 encoded-word for headers, attachment
  metadata extraction. 7 unit tests including the regression that
  broke "body truncated at first blank line".
  *MIMEParser.swift, QQMailService.swift, MIMEParserTests.swift*
- **F1** — wizard click feedback fix: connecting state shown
  synchronously, network call moved to background `Task`. Inline error
  retry without leaving the connecting view. *AccountWizardView.swift*
- **F2/F3** — body text selection (`.textSelection(.enabled)` on
  subject/sender/body/closing); `MailBodyCleaner` defensive MIME
  scrub. *MessageDetailView.swift, MailBodyCleaner.swift*
- **F4** — list/detail drag handle (`VerticalResizer`), persisted via
  `@AppStorage("mailclient.layout.listWidth")`. Trailing hairline on
  MessageList removed to avoid double line. *Resizer.swift, RootView.swift,
  MessageListView.swift*

### Why
Real test of QQ inbox surfaced three separate body issues at once:
list/detail ratio felt wrong, body wasn't selectable, and the bodies
displayed raw MIME like `----==_mimepart_xxx`. Root cause traced to
`data.split(separator: "\r\n\r\n")` splitting on every blank line in
the body — fixed via complete MIME parser rewrite. The header/body
split followed naturally as the persistence layer matured.

### Tests
- `xcodebuild test` — 17/17 passed (10 from MIMEParser + 7 base)

### Next
- F8 attachment chips polish, F10/F11/F12, narrow window work.

---

## 2026-04-25 — Phase 1 persistence foundation

### What landed
- `Persistence/SQLite.swift` — actor-wrapped sqlite3 wrapper, WAL mode,
  128 MB mmap, 8 MB page cache. ~250 LOC, zero deps.
- `Persistence/MailDatabase.swift` — single-connection owner, linear
  migrations.
- `Persistence/Schema/V1_Initial.swift` — accounts / folders / messages
  / attachments / sync_state / drafts + FTS5 virtual table + triggers.
- `Persistence/DAO/AccountDAO.swift`, `FolderDAO.swift`, `MessageDAO.swift`
- `Services/Providers/MailProviderAdapter.swift` — new protocol
  (header-first, UID-keyed, capability flags), wire types `RemoteHeader`
  / `RemoteBody` / `RemoteFolder`, `MailProviderAdapterRegistry`.
- `docs/architecture.md` rewrite, `docs/dependencies.md` evaluation.

### Why
The in-memory `[MailMessage]` published by `AppState` was the eventual
memory hotspot, and POP3 alone wouldn't unlock multi-folder. Both lead
to "we need a real local cache". Building the protocol surface for
adapters at the same time means Phase 3 swaps one file in instead of
restructuring.

### Tests
- `xcodebuild test` — 7/7 passed (migration + DAO round-trips)

### Next
- F7 wire SQLite cache to AppState, F8 structured attachments.

---

## 2026-04-24 — UI scaffolding complete

### What landed
- Design system (`DS.Color`, `DS.Font`, `DS.Motion`, `DSIcon`) per the
  Claude-design canvas in `docs/Design/mailstream/`
- All routes: mail (3-pane), onboarding, account wizard (4-step
  stepper), inline settings, command palette overlay, search,
  multi-tab compose
- Animation pass (matchedGeometryEffect, hover lift, pulse ring,
  status banner toast)
- Anti-aliasing pass — `dsCard()` modifier centralizes
  `fill + clipShape + strokeBorder + compositingGroup`
- All sidebar / command-palette / detail toolbar / settings
  interactions wired

### Why
Before any data layer work makes sense, the shape of the app needs to
be agreed on. The design canvas drove this; we matched it as a static
prototype first.

### Tests
- `xcodebuild test` — 2/2 passed (in-memory repo, AppState bootstrap)

### Next
- Phase 1 persistence groundwork, real MIME parsing.
