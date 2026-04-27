# Code & Design Conventions

> **Purpose.** Make every file in this repo feel like the same author
> wrote it. When something is *not* in this doc, prefer the existing
> codebase's pattern over reinventing.

---

## 1. Module / folder layout

Mirrors `architecture.md`. New files go where they fit the dependency
direction:

```
MailClient/
├── App/                  Composition root, AppState, routing, scene
├── Core/Models           Pure value types — no SwiftUI / no IO
├── Core/Services         Domain services, providers, sync
├── Core/Database         Legacy persistence (will fold into Persistence)
├── Core/Utilities        Pure helpers (MIMEParser, MailBodyCleaner, …)
├── Persistence/          SQLite cache layer (one connection, many DAOs)
├── Services/Providers/   MailProviderAdapter implementations
├── Features/<Screen>/    SwiftUI screen + screen-local subviews
├── SharedUI/             Design system + reusable components
├── Platform/             macOS-specific bridging
├── Resources/            Asset catalog, AppIcon
└── Tests/                Unit + integration tests
```

**Dependency rules** (enforced by review, not tooling — yet):

- `App` depends on every product layer.
- `Core/Models` must not import `SwiftUI`.
- `Persistence` must not import `Services` or `Features`.
- `Services` may depend on `Core` and `Persistence` only.
- `Features` may depend on `Core`, `SharedUI`, `App` (for AppState).
- `SharedUI` stays presentation-only.

When in doubt: imagine the `Core` layer in a Linux Swift package — it
should compile.

---

## 2. Swift style

### Access modifiers

We're a single target. **Default to `internal`.** Don't write `public`
unless we're publishing as a real Swift package. Use `private` for
file-locals. Use `fileprivate` only when you need cross-type access
inside one file.

### Naming

- Types: `UpperCamel`. Acronyms stay uppercase: `URL`, `IMAP`, `UID`.
- Methods / properties / locals: `lowerCamel`.
- Booleans: `is*` / `has*` / `should*` / `can*` / `did*`. Never bare
  nouns (`active` → `isActive`).
- Async functions don't need an `Async` suffix; the keyword is
  signal enough.
- Closures that fire on completion: `onSomething: () -> Void`. Past
  tense for events, present tense for capabilities.

### File header

No license boilerplate (we'll add one at distribution time). One blank
line between `import` and the first type. Keep imports minimal and
sorted: stdlib → Foundation → SwiftUI / AppKit → first-party.

### Type bodies

Order:

1. Nested types
2. Stored properties (private then public)
3. Initializers
4. Public methods
5. Private methods
6. `// MARK: -` only when a file has > 2 logical groups

Use `// MARK: – Section` with an em-dash so all marks render with the
same gutter spacing in Xcode.

### Comments

- **The "why" beats the "what".** Don't restate the code.
- For tricky workarounds, link to the bug entry in
  `troubleshooting.md`.
- `// TODO:` is fine if the rationale is committed in the same PR;
  otherwise file an issue and reference its number.
- Doc comments (`///`) on public-ish API and on anything non-obvious
  to a reader who hasn't seen the rest of the file.

### Concurrency

- Long-lived shared state lives in an `actor`.
- `@MainActor` for view models / AppState only.
- Closures crossing actor boundaries must be `@Sendable` (Swift 6
  enforces this; we anticipate).
- Cancel in-flight tasks before kicking new ones — see the body-load
  pattern in `AppState.onSelectedMessageChanged`.
- No `DispatchQueue.global()` for new work — use `Task.detached` (but
  prefer staying in an actor).

### Error handling

- **Throw, don't return optionals**, when the failure is meaningful.
- Reserved error type: `MailServiceError`. Add a case rather than
  invent a new error type for every call site.
- Errors that bubble to UI become `appState.mailboxStatusMessage` or
  `appState.snoozeBannerMessage` — never a fatal alert.

---

## 3. UI conventions

### Design system tokens

Always go through `DS`:

- Colors: `DS.Color.ink`, `DS.Color.accent`, …
- Typography: `DS.Font.sans(13.5)` / `mono(11)` / `serif(22, weight:)`
- Radii: `DS.Radius.sm/md/lg`
- Strokes: `DS.Stroke.hairline`
- Motion: `DS.Motion.snap` / `surface` / `hover` / `press`

Hard-coded `Color(...)` / `Font.system(...)` is a smell. If a token
doesn't exist for what you need, propose adding it before introducing
a one-off.

### Composition primitives

- `dsCard(cornerRadius:fill:stroke:)` — fill + clipShape + strokeBorder
  + compositingGroup. Always use this instead of hand-rolling the
  combo. Anti-aliasing baseline.
- `hoverLift()` — scales 1.04 on hover, 0.97 on press, with the
  standard motion tokens. Apply to any tappable surface.
- `compositingGroup()` — required wherever overlapping translucent
  layers might subpixel-align differently.
- Banners → `StatusBanner` + `appState.snoozeBannerMessage`. Don't
  build one-offs.

### Animations

- Tie `.animation(_, value:)` to **stable identity** (`message.id`,
  not `body`). See the [layout flashing
  troubleshooting](./troubleshooting.md#layout-flashing-during-list-resize--image-load).
- Never animate height / size unless you've thought about the feedback
  loop.
- `repeatForever` is reserved for `PulseRing` and similar — and only
  when the view is unconditionally on screen.

### Accessibility

- Every interactive surface gets an `accessibilityLabel` if its glyph
  is the only signal.
- `.help(...)` for hover tooltips on icon buttons.
- Scroll surfaces respect `NSCursor.resizeLeftRight` etc. when the
  cursor changes role (see `VerticalResizer`).

### Adaptive layout

`AppTheme.layout(for:)` is the single source of layout truth. Three
breakpoints: drilldown (< 840), compact (840–1180), regular (1180+),
wide (1480+). Never read `geometry.size.width` directly inside a
view — go through `LayoutMetrics`.

### View files

- One screen per directory under `Features/<Screen>/`.
- Top-level `*View.swift` is the entry. Sub-views live as `private
  struct` in the same file unless they grow past ~150 lines.
- Reusable sub-views move to `SharedUI/Components/`.

---

## 4. Persistence conventions

### Schema

- Primary keys are `TEXT` UUIDs for app-owned entities, `INTEGER
  AUTOINCREMENT` for join tables.
- All times stored as **UNIX milliseconds** (`INTEGER`).
- Strings always UTF-8; SQLite handles this natively.
- `FOREIGN KEY` with `ON DELETE CASCADE` so removing an account wipes
  its data.
- Indexes follow the access pattern, not the column count.

### Migrations

- Linear, never edited once shipped. To change V1, add V2 that alters.
- Each migration is its own `Vn_*.swift` under `Persistence/Schema/`.
- `MailDatabase.migrate()` runs them in a single transaction per step.
- Test the upgrade path in `Tests/Persistence/`.

### DAO layer

- DAOs are `struct`. They hold a reference to the `MailDatabase`
  actor; they don't cache.
- One DAO per logical entity (`AccountDAO`, `MessageDAO`, …).
- Read methods return value types; write methods return `Void` or the
  affected row id.
- Wrap multi-statement writes in `BEGIN IMMEDIATE` / `COMMIT` for
  bulk loads.

### Repositories

- Repositories implement domain protocols (e.g. `MailRepository`)
  and translate between domain types and DAO row shapes.
- One repository per protocol. Do not stack repositories.

---

## 5. Tests

- **Naming**: `<thing><Behavior>` — `bodyStoreCachesAndEvictsLRU`,
  not `testBodyStore`.
- Use `@Test` (Swift Testing). One assertion per intent; multiple
  `#expect` lines per test are fine.
- Pure-logic tests live next to their domain (e.g. `MIMEParserTests`).
- Persistence tests open a fresh DB at a `NSTemporaryDirectory()` path
  per test.
- View tests are deferred until snapshot infrastructure exists; for
  now, smoke-test by running the app.

---

## 6. Git / PR

### Commit messages

```
<area>: <imperative summary>

<optional body — what & why, never restate the diff>

<optional trailers — Closes #N, Refs #M>
```

`<area>` is one of: `app`, `core`, `persistence`, `services`,
`features`, `sharedui`, `platform`, `tests`, `docs`, `build`. If a
commit straddles areas, pick the dominant one and mention the others
in the body.

### Branches

- `main` — always green. CI-DMG ships from here.
- `phase-N-*` — current architectural phase work
- `fix/*` — single-issue fixes
- `docs/*` — docs-only changes don't need a phase branch

### Pull requests

- Title = first line of the planned commit.
- Description references the relevant phase / F-id from
  [`phases.md`](./phases.md).
- Run `xcodebuild test` before opening the PR. CI runs it again.
- If a change should be visible to the user, add a screenshot or a
  20-second screen recording.

---

## 7. Documentation

- Every doc file in `docs/` has a one-paragraph header explaining
  what it's for.
- Cross-link with relative paths (`./architecture.md`).
- Code samples in fenced blocks tagged with the language.
- Diagrams: ASCII first; if it really needs to be visual, add an
  `.png` next to the doc.
- Update [`devlog.md`](./devlog.md) at the end of every session.
- Update [`troubleshooting.md`](./troubleshooting.md) the moment you
  fix a non-trivial bug — you'll have all the context loaded.

---

## 8. Definition of done

A change is done when:

1. `xcodebuild build` is green.
2. `xcodebuild test` is green.
3. Lint warnings introduced by the change are addressed.
4. Public-facing behavior is documented in `phases.md` or `devlog.md`.
5. If you fixed a bug, the fix is in `troubleshooting.md`.
6. If you added a dep, it's noted in `dependencies.md`.
7. The PR description names the user-visible change and links the
   F-id (e.g. F11 — HTML rendering).
