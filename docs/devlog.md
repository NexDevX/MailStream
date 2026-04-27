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
