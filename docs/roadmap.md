# Roadmap

> **Living document.** Status here always matches the current branch's
> reality. When a phase finishes, mark it ✅ and link the relevant PR.
> See [`phases.md`](./phases.md) for the per-feature changelog and
> [`devlog.md`](./devlog.md) for the dated narrative.

## Vision

MailStream is a **professional desktop email aggregator** for macOS:
keyboard-first, multi-account, locally-encrypted, with a calm editorial
visual identity instead of a cluttered dashboard. AI summary is on the
roadmap but not gating any release.

Three principles drive every architectural decision:

1. **Header-first I/O.** Steady-state RAM is bounded; bodies are paged in
   on demand. No "load 50 000 messages into an array" anti-patterns.
2. **Provider-agnostic core.** Adapters slot in behind a single protocol;
   the rest of the app speaks one model.
3. **Zero external runtime dependencies until they pay for themselves.**
   See [`dependencies.md`](./dependencies.md).

## Status snapshot

| Phase | What it delivers | State |
| ----- | ---------------- | ----- |
| Phase 0 | Design system, 3-pane layout, all routes (mail / settings / wizard / search / compose / onboarding), animations, anti-aliasing | ✅ shipped |
| Phase 1 | SQLite cache (DAOs + migrations), MailProviderAdapter protocol, capability flags | ✅ shipped |
| Phase 2 | Header/body split (`MailMessageBody`), `MailMessageBodyStore` LRU, lazy detail load, FTS5 search hookup | ✅ shipped |
| Phase 2.5 | Real MIME parser (`MIMEParser`), HTML rendering via `WKWebView`, structured `MailAttachment`, scroll passthrough, narrow-window adaptation | ✅ shipped |
| Phase 3 | Real IMAP (hand-rolled — see decisions log), OAuth2 via AppAuth, multi-folder sync, Sent / Drafts / Junk | 🟡 in progress (A2/A3/A4/A5 shipped) |
| Phase 4 | Background sync (`NSBackgroundActivityScheduler`), body cache eviction, `@ScaledMetric` on Retina/4K, Settings privacy controls | 🔵 planned |
| Phase 5 | Threading view, batch select, AI summary card real implementation, signed/notarized release | 🔵 planned |

## Phase 3 — IMAP & OAuth (next)

Goal: a single email account works end-to-end through real IMAP
(POP3 is a temporary stand-in). Sent, Drafts, Junk become reachable
folders. Gmail and Outlook gain OAuth2 entry points.

### Workstream A — IMAP foundation

| Step | State | Detail |
| ---- | ----- | ------ |
| A1 | ⏭ skipped | `swift-nio-imap` deferred — see decisions log 2026-04-27. We hand-rolled `IMAPClient` over `SecureMailStreamClient` instead, ~530 LOC for one provider. |
| A2 | ✅ 2026-04-27 | `Services/Providers/IMAPClient.swift` + `IMAPResponseParser.swift` (12 tests). |
| A3 | ✅ 2026-04-27 | `GenericIMAPAdapter` + `QQMailAdapter` thin config. |
| A4 | ✅ 2026-04-28 | `MailSyncEngine` replaces `MailSyncService`. Stable `MailMessage.id` via `SHA1(account ‖ UID)`. 8 tests. |
| A5 | ✅ 2026-04-28 | `AppContainer.live` wires `MailProviderAdapterRegistry([QQMailAdapter()])`; legacy `MailProvider` / `QQMailProvider` / SMTP helpers retired. |
| A6 | ✅ 2026-04-28 | `MailRepository.upsertFolders` / `upsertRemoteHeaders` / `listFolders` land. Sync engine persists every server folder, fetches headers for the four `SidebarItem`-navigable roles (inbox/sent/drafts/trash), and writes through the new path so real IMAP UID + `messageID` + folder PK survive on disk. Read path's `compose` now maps `folderRole → SidebarItem`. Sidebar still uses the static enum — folder-row UI is deferred. 1 new round-trip test. |
| A7 | ✅ 2026-04-28 | IMAP-UTF7 mailbox name decoding (`IMAPResponseParser.decodeMailboxName`). 5 tests. Was a follow-up after live smoke turned up `&UXZO1mWHTvZZOQ-` from QQ. |
| A8 | ✅ 2026-04-28 | Live smoke harness — `IMAPLiveSmokeTests`, gated on `docs/password.TXT`, exercises full validate → list → fetchHeaders → fetchBody chain end-to-end against a real account. |

**Done when:** QQ account connects, all server folders visible in
sidebar, message body lazy-loads via `BODY[]` IMAP fetch, send goes
through SMTP. Sidebar showing **real** folder names (Chinese / custom
folders) instead of the static enum is the last piece — tracked
separately as a sidebar-UI task; the persistence shape behind it is
now ready.

### Workstream B — OAuth2 entry points

| Step | Detail |
| ---- | ------ |
| B1 | Add `AppAuth-iOS` via SPM |
| B2 | `Services/Auth/OAuthCoordinator.swift` — owns `ASWebAuthenticationSession` for the redirect flow, hands tokens to `CredentialsStore` |
| B3 | `GmailAdapter` skeleton — Gmail API for headers + IMAP for body, OR pure IMAP with XOAUTH2 (decide after probe) |
| B4 | `OutlookAdapter` skeleton — Microsoft Graph API |
| B5 | `AccountWizardView` shows OAuth providers separately from IMAP-with-app-password providers |

**Done when:** "添加 Gmail 账号 → 浏览器授权 → 回到 app → 同步收件箱"
works end to end.

### Workstream C — Sync engine polish

| Step | Detail |
| ---- | ------ |
| C1 | `SyncStateDAO` cursor advancement, UIDVALIDITY change detection (full re-sync trigger) |
| C2 | Per-folder fetch prioritization (inbox first, archive last) |
| C3 | Push: IMAP IDLE for accounts that support it; poll fallback otherwise |
| C4 | Send-on-network-restore: queue outgoing messages when offline |

## Phase 4 — Adaptivity & energy

| Item | Why |
| ---- | --- |
| `MailDatabase.evictBodies(olderThan: 7d)` triggered by app-idle event | Disk + memory bounded over months of use |
| `NSBackgroundActivityScheduler` for periodic sync | Coalesce with system activity windows |
| `@ScaledMetric` audit | Retina / 4K row heights, font metrics |
| Privacy / images settings page | User toggle for "load remote images" + "block tracking pixels" — currently default-on per product decision |
| Window restoration | Last-selected message id + scroll position survives relaunch |

## Phase 5 — Threading & batch

| Item | Why |
| ---- | --- |
| Conversation view (group by `thread_id` / Gmail threadId) | Email is conversation, not message stream |
| Batch select + bulk archive / trash / mark-read | Power users |
| Real AI summary integration via Anthropic / OpenAI | Currently stubbed with deterministic seed text |
| Code-signed + notarized DMG release pipeline | Public distribution |
| Lint + format in CI (SwiftFormat) | Codebase past ~20 kLOC |

## Non-goals

We deliberately do **not** plan to ship:

- iOS / iPadOS variant — different ergonomics, would dilute focus
- Built-in calendar / contacts — out of scope
- Web client — would require a server tier
- Plugin / extension system — premature; revisit if user count justifies

## Decisions log

When a non-obvious architectural choice is made, record it here with the
date and rationale. The decision matters more than the alternatives.

- **2026-04-25** — Hand-rolled SQLite over GRDB / SQLite.swift. Reason:
  zero-deps; we use ~5 % of GRDB. See `dependencies.md`.
- **2026-04-26** — Hand-rolled MIME parser (`MIMEParser`). Reason: only
  serious option is mailcore2 (C++); ours is 280 LOC + 7 tests + fully
  understood by us.
- **2026-04-26** — `MailMessage` split into header / `MailMessageBody`
  with separate repository planes. Reason: 5 000-message inbox would
  cost ~50–500 MB resident RAM with bodies inline; lazy load via LRU
  caps it at ~3 MB header + ~30 KB × cache size.
- **2026-04-27** — Default-on remote image loading in HTML body.
  Reason: privacy gain didn't outweigh the broken-image UX confusion
  for our initial audience. The toggle moves to Settings in Phase 4.
- **2026-04-27** — Hand-rolled `NSScrollView` traversal to disable
  internal WKWebView scrolling, plus `ScrollPassthroughWebView`
  subclass forwarding `scrollWheel(with:)`. Reason: there's no public
  API for this; the alternatives (overlay tricks, pure JS scroll
  forwarding) were either visually wrong or laggy.
- **2026-04-27** — Hand-rolled `IMAPClient` over the existing
  `SecureMailStreamClient` instead of adopting `swift-nio-imap`.
  Reason: NIOIMAP is a `ChannelHandler` pair with no high-level
  client — using it would mean ~800–1500 LOC of NIO orchestration
  on top of the actual adapter. For one provider (QQ) the hand-rolled
  client is ~530 LOC total and keeps deps at zero. Revisit when Gmail
  (XOAUTH2) and Outlook (Graph) earn the NIO substrate.
- **2026-04-28** — Renamed `MailSyncService` → `MailSyncEngine` and
  retired the entire `MailProvider` / POP3 path (`QQMailProvider`,
  `SMTPMessageBuilder`, `RawInternetMessageParser`,
  `MailAddressParser`). The old type names were carrying a "legacy
  POP3" mental model that the implementation had outgrown. Everything
  now goes through `MailProviderAdapter` + `MailProviderAdapterRegistry`.
- **2026-04-28** — Stable `MailMessage.id` derived from
  `SHA1(accountID || remoteUID.bigEndian)`, folded into a UUID, on
  every map from `RemoteHeader`. Reason: the old random-UUID-per-parse
  policy made every refresh invalidate the body cache, killed selection
  state, and meant the SQLite unique constraint on
  `(account, folder, remote_uid)` couldn't dedupe. SHA1 is fine here
  because the input space is tiny and the property we care about is
  determinism, not collision resistance — `CryptoKit` would pull a
  real dependency into Core for no benefit.
- **2026-04-28** — Cache last-loaded HTML in
  `HTMLMessageBodyView.Coordinator` and short-circuit
  `view.loadHTMLString(...)` on identical content. Reason: SwiftUI
  calls `updateNSView` on every ancestor re-render; reloading the
  WebView each time visually flashed white and re-fetched images.
  See `troubleshooting.md` "HTML body flickers / white-flashes on
  unrelated UI changes".
- **2026-04-28** — Hand-rolled IMAP-UTF7 (modified UTF-7) decoder for
  mailbox names. Reason: QQ Mail returns custom Chinese folders like
  `&UXZO1mWHTvZZOQ-` (= `其他文件夹`); Foundation has no IMAP-UTF7
  codec, only standard UTF-7 (which differs in base64 alphabet and
  padding rules). 50 LOC + 5 unit tests beats pulling a third-party
  IMAP library for one transformation.
- **2026-04-28** — `IMAPLiveSmokeTests` gated on the presence of
  `docs/password.TXT` (gitignored), not on an env var. Reason: env
  vars don't reliably propagate through `xcodebuild test` to the
  Swift Testing runner; file-presence is observable both at suite
  registration time (`@Suite(.disabled(if:))`) and inside test
  bodies, with no extra command-line plumbing.
- **2026-04-28** — Repository gains `upsertFolders` /
  `upsertRemoteHeaders` / `listFolders` (workstream A6). Sync engine
  writes through this provider-shape path so real IMAP UID +
  Message-ID + folder PK survive on disk without round-tripping
  through `MailMessage`. Read path's `compose` derives the user-
  facing `SidebarItem` from the persisted folder role via a JOIN,
  which means Sent / Drafts / Trash now actually populate when
  the sync engine fetches their folders. Sidebar UI still uses the
  static enum until folder-row rendering lands; the data is ready.
