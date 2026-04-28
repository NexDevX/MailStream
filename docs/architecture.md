# MailStream Architecture

## Goals

- Keep UI work fast without letting view code absorb business logic
- Make mailbox data sources replaceable without rewriting screens
- Persist a local cache so users don't pay network cost on every launch
- Keep macOS-specific behavior isolated from domain and feature code
- Tight memory budget: header-only in steady state, body on demand
- Preserve a clean path from local build to CI release artifacts

## Layered Topology

```
┌─────────────── UI (SwiftUI) ─────────────┐
│  Features  ⇄  AppState (@MainActor)      │
└────────────────────┬─────────────────────┘
                     │ Combine publishers
┌────────────────────┴─────────────────────┐
│  Application Services (actor)            │
│   · MailSyncEngine                       │
│   · AccountManager                       │
└──┬───────────────────────────┬───────────┘
   │                           │
┌──┴────────────────────┐  ┌───┴────────────────────┐
│  Provider Adapters    │  │  Persistence (SQLite)  │
│   · QQMailAdapter     │  │   · MailDatabase       │
│   · GmailAdapter      │  │   · MessageDAO         │
│   · OutlookAdapter    │  │   · FolderDAO          │
│   · ICloudAdapter     │  │   · AccountDAO         │
│   · GenericIMAP       │  │   · SyncStateDAO       │
└───────────────────────┘  └────────────────────────┘
                                     │
                          ~/Library/Application Support/
                                MailStream/mailstream.sqlite
```

## Module / Folder Layout

```
MailClient/
├── App/                  Composition root, AppState, routing, scene
├── Domain/ (Core/Models) Pure data types — no SwiftUI / no IO
├── Persistence/          SQLite cache layer (one connection, many DAOs)
│   ├── SQLite.swift
│   ├── MailDatabase.swift
│   ├── Schema/V1_Initial.swift
│   └── DAO/AccountDAO|FolderDAO|MessageDAO|SyncStateDAO.swift
├── Services/
│   ├── Providers/        Adapters per backend (QQ, Gmail, Outlook, …)
│   ├── MailSyncEngine    Coordinates fetch → DAO → publish
│   ├── AccountManager    Owns credentials + status
│   └── CredentialsStore  Keychain wrapper
├── Features/             SwiftUI screens (header-summary driven)
├── SharedUI/             Design system + reusable controls
├── Platform/             macOS-specific bridging
├── Resources/
└── Tests/
```

## Dependency Rules

- `App` may depend on every product layer
- `Domain` must not import `SwiftUI` or `Persistence`
- `Persistence` must not import `Services` or `Features`
- `Services` may depend on `Domain` and `Persistence` only
- `Features` may depend on `Domain`, `SharedUI`, `App` (for AppState)
- `SharedUI` must stay presentation-only

## Data Flow (Steady State)

1. App launch → `AppContainer` opens `MailDatabase` (runs migrations)
2. `AccountDAO.all()` populates `AppState.accounts` synchronously
3. `MessageDAO.summariesForAccount(...)` hydrates the inbox **header-only**
4. UI renders from summaries (≤ 1 KB per row → 5 MB for 5 000 messages)
5. User opens a message → `MessageDAO.body(id:)` hits cache, or
   `MailSyncEngine.fetchBody(...)` triggers provider call + `storeBody`
6. `MailSyncEngine.refresh(account:)` runs every N min:
   a. List folders via adapter
   b. For each folder, read `SyncStateDAO.cursor`, fetch headers `> lastUID`
   c. Bulk-upsert via `MessageDAO.upsertHeader` inside a transaction
   d. Write new `SyncCursor` back

## Memory Strategy

- **Headers only in RAM**. Body columns are nulled out via
  `MailDatabase.evictBodies(olderThan:)` on app idle (default: 7 days).
- `MailMessageSummary` is a value type with only essentials; bulky
  `bodyText` / `bodyHtml` live in SQLite and are dropped after view.
- LazyVStack ensures only visible rows allocate row views.
- WAL mode + `PRAGMA cache_size=-8000` caps page cache around 8 MiB.
- `mmap_size = 128 MiB` so the OS — not us — manages the working set.

## Provider Adapter Contract

Every adapter is **stateless** and `Sendable`. It maps three operations
into the cache-friendly shape:

```
listFolders(account)          → [RemoteFolder]
fetchHeaders(folder, cursor)  → ([RemoteHeader], newCursor)
fetchBody(folder, remoteUID)  → RemoteBody
send(message)                 → Message-ID?
updateFlags(remoteUID, flags) → ()
```

Adapters never write the DB. The sync engine is the single writer.

## Schema (V1)

| Table          | Purpose                                                |
| -------------- | ------------------------------------------------------ |
| `accounts`     | Connected mailboxes (mirrored to `MailAccount`)        |
| `folders`      | Per-account folders, mapped to a normalized role enum  |
| `messages`     | UID-keyed headers; body is lazy via `body_loaded`      |
| `attachments`  | Metadata; binaries live on disk under `Caches/`        |
| `sync_state`   | Per-folder cursor (lastUID, UIDVALIDITY, MODSEQ)       |
| `drafts`       | Local-only compose drafts                              |
| `messages_fts` | FTS5 virtual table for unified search                  |

All times are UNIX milliseconds. Strings are UTF-8. FK CASCADE on delete.

## Migrations

Migrations are linear. Each version `Vn` adds a Swift file under
`Persistence/Schema/Vn_*.swift`. `MailDatabase.migrate()` checks
`schema_version` and applies missing steps, in a single transaction per
step. Never edit a shipped V1 — always add V2.

## Release Flow

- `make package` / `./scripts/build_dmg.sh` — local DMG
- `push main` — GitHub Actions → `latest-main` prerelease
- `push v* tag` — GitHub Actions → tagged release

## Roadmap

`MailSyncEngine` is wired end-to-end as of 2026-04-28: production
`AppContainer` registers `QQMailAdapter` through
`MailProviderAdapterRegistry`, and the legacy `MailProvider` /
`QQMailService` POP3 path is gone. Live IMAP smoke against a real
QQ account passes (folder list, header window, body fetch, MUTF-7
decoding). See [`roadmap.md`](./roadmap.md) for the live status of
the rest:

- 🔜 **A6** — persist the folder list per account; sidebar reads from
  the `folders` table instead of the static `MailSidebarItem` enum;
  give the repository a `RemoteHeader` upsert path so `remoteUID`,
  `messageID`, `threadID` round-trip without going through `MailMessage`.
- 🔜 **GmailAdapter** (OAuth2 + Gmail API) and **OutlookAdapter**
  (MSAL + Graph) — Workstream B.
- 🔜 Per-folder sync prioritization (inbox first, archive last).
- 🔜 Background polling via `NSBackgroundActivityScheduler`.
- 🔜 A single `Tests/Persistence/` suite covering migrations + DAO.
