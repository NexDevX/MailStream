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
| Phase 3 | Real IMAP via `swift-nio-imap`, OAuth2 via AppAuth, multi-folder sync, Sent / Drafts / Junk | 🟡 next |
| Phase 4 | Background sync (`NSBackgroundActivityScheduler`), body cache eviction, `@ScaledMetric` on Retina/4K, Settings privacy controls | 🔵 planned |
| Phase 5 | Threading view, batch select, AI summary card real implementation, signed/notarized release | 🔵 planned |

## Phase 3 — IMAP & OAuth (next)

Goal: a single email account works end-to-end through real IMAP
(POP3 is a temporary stand-in). Sent, Drafts, Junk become reachable
folders. Gmail and Outlook gain OAuth2 entry points.

### Workstream A — IMAP foundation

| Step | Detail |
| ---- | ------ |
| A1 | Add `swift-nio-imap` + `swift-nio-ssl` via SPM through `project.yml` |
| A2 | New `Services/Providers/GenericIMAPAdapter.swift` implementing `MailProviderAdapter` |
| A3 | Migrate `QQMailService` content into `QQMailAdapter` (subclass / config of GenericIMAP) |
| A4 | `MailSyncEngine` (new) — coordinator that owns folder enumeration, cursor advancement, body fetch on demand. Replaces the legacy refresh-all loop in `MailSyncService`. |
| A5 | Wire `AppContainer` to register adapters via `MailProviderAdapterRegistry` |
| A6 | Persist folder list per account; sidebar shows real folders, not the static enum |

**Done when:** QQ account connects, all server folders visible in
sidebar, message body lazy-loads via `BODY[]` IMAP fetch, send goes
through SMTP using the same NIO substrate.

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
