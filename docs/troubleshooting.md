# Troubleshooting

> Catalogue of bugs we've actually hit, plus the fix that stuck. The
> goal is to be searchable: when something breaks again, grep here
> first. Each entry has a **Symptom**, **Root cause**, **Fix**,
> **Detection**.

## How to add an entry

```
## Title (one line, the symptom phrase you'd grep for)

**Symptom.** What the user sees / what tests fail.

**Root cause.** The actual mechanism — not a guess. Bonus points for a
minimal repro.

**Fix.** What we changed. File + brief diff sketch.

**Detection.** How we'd notice it again — a regression test, a log
line, an assertion. If we can't detect it, write a TODO to add the
detector.
```

---

## HTML body height grows infinitely on open

**Symptom.** Opening any HTML email kicks the detail pane into endless
upward growth — the scrollbar shrinks, the WebView re-measures, repeats
forever. Especially visible with marketing emails that have many
images.

**Root cause.** Classic `ResizeObserver` feedback loop. We attached a
`ResizeObserver` to both `document.documentElement` and
`document.body`. When SwiftUI sized the WKWebView frame to the reported
height, the documentElement size literally changed (it *is* the
viewport), the observer fired again, we reported a slightly larger
height, the frame grew, and so on.

**Fix.** [HTMLMessageBodyView.swift](../MailClient/Features/MessageDetail/HTMLMessageBodyView.swift)
`ScriptHost.heightReporterJS` — replaced `ResizeObserver` with an
event-driven measurement set:

- `requestAnimationFrame` for initial paint
- `document.fonts.ready` for late font loads
- per-`img` `load` / `error` for image-resolved layouts
- `setTimeout(80ms)` + `setTimeout(200ms)` as belt-and-suspenders

Measurement source narrowed to `body.scrollHeight` only — that's the
intrinsic content extent and *doesn't* track the viewport. Threshold
of 2 px in JS, 4 px in Swift, `min(20_000, ...)` cap to prevent runaway.

Also removed two CSS rules that were retriggering layout on width
change: `body * { box-sizing: border-box }` and `td/div { max-width:
100% !important }`.

**Detection.** No automated test yet. Visible regression — would show
up as soon as you open any HTML email. TODO: add a snapshot test that
asserts the WebView frame stabilizes within 3 reports.

---

## Scroll wheel over HTML body doesn't scroll the page

**Symptom.** Mouse over the rendered HTML email, scroll wheel — nothing
happens. Move cursor to the strip of empty padding around the email,
scroll — works.

**Root cause.** macOS `WKWebView` wraps its document in a private
`NSScrollView`. Even with scrollers and elasticity disabled, that
internal scroll view still **receives** wheel events because it's the
topmost view under the cursor. Events never propagate to the outer
SwiftUI ScrollView.

**Fix.** [HTMLMessageBodyView.swift](../MailClient/Features/MessageDetail/HTMLMessageBodyView.swift)
introduced `ScrollPassthroughWebView: WKWebView` that overrides
`scrollWheel(with:)` and forwards directly to `nextResponder` without
calling super. Clicks, text selection, link activation use different
responder methods so they're unaffected.

**Detection.** Manual scroll test on any email. If we ever rebuild on
top of stock `WKWebView`, this one returns immediately.

---

## Body shows raw MIME headers and boundaries

**Symptom.** Detail pane displays text like
`----==_mimepart_69e9852817601_11b110824e\nContent-Type: text/plain;
charset=UTF-8\nContent-Transfer-Encoding: 7bit` mixed into the body.

**Root cause.** The old `RawInternetMessageParser.parse` used
`data.split(separator: Data("\r\n\r\n".utf8))`. `Data.split` splits on
**every** occurrence of the separator — so the body got truncated at
its first blank line, and what looked like "body" in the
`components[1]` slot was the next MIME part's headers.

**Fix.** Wrote a proper recursive MIME parser at
[MIMEParser.swift](../MailClient/Core/Utilities/MIMEParser.swift):

- `splitOnce(_:separator:)` splits at the **first** occurrence only
- `walk()` recurses through `multipart/*` children
- `multipart/alternative` picks text/plain over text/html
- per-part `Content-Transfer-Encoding` (base64, quoted-printable, 7bit, 8bit)
- per-part charset via `CFStringConvertIANACharSetNameToEncoding`
- RFC 2047 encoded-word decode for headers (`=?UTF-8?B?…?=`)

**Detection.** [MIMEParserTests.swift](../MailClient/Tests/MIMEParserTests.swift)
covers the regression directly (`bodyIsNotTruncatedAtFirstBlankLine`).
7 unit tests in total.

---

## Layout flashing during list resize / image load

**Symptom.** While dragging the list/detail divider OR while images in
an HTML email finish loading, the entire body content flashes /
crossfades on every frame.

**Root cause.** The bodyView had `.animation(DS.Motion.surface, value:
body)` and `.animation(DS.Motion.surface, value: isLoading)`. Body
identity changes on every height tick (cache hit returns same object,
but SwiftUI's diff still reschedules), spring-animating each one
produced visible flicker. Image loads also retrigger height reports.

**Fix.** [MessageDetailView.swift](../MailClient/Features/MessageDetail/MessageDetailView.swift)
`bodyView` — removed the inner `.animation(_, value: ...)` modifiers.
Only the outer `.animation(.spring..., value: message.id)` remains —
that's tied to message identity so it only fires on selection change.

Height changes are immediate (no animation), which is correct: the
WebView reports a new measurement and we apply it.

**Detection.** Manual smoke. TODO: add a CI test that selects a
message, simulates body delivery, and snapshots the frame stability.

---

## "Add account" click feels laggy

**Symptom.** Clicking "完成接入" in the wizard freezes for ~1–2s before
any UI feedback.

**Root cause.** The `Task { await connect() }` was async and
non-blocking, but the wizard view didn't transition until
`currentStep = .done` was set — which only happened after the network
call returned. Subjectively the user clicks and nothing moves.

**Fix.** [AccountWizardView.swift](../MailClient/Features/AccountWizard/AccountWizardView.swift)
— flip to a transient `.connecting` step **synchronously** in the
button action with `withAnimation(DS.Motion.surface)`, then kick the
network task. The connecting view is a small `PulseRing` + status
text. Errors land back in the same view with retry / back-to-form
buttons.

**Detection.** None. TODO: snapshot test "wizard step transitions in
< 1 frame after tap".

---

## Test target finds symbols from main target

**Symptom.** Tests reference types that are `internal` to the main
target with no special import.

**Why it works.** The test target is configured with `BUNDLE_LOADER` /
`TEST_HOST` pointing at `MailStrea.app`, and `@testable import MailStrea`
exposes internal symbols. See `project.yml`. No action needed unless
the symbol is `private`.

---

## `xcodebuild test` warnings about WebKit RBS assertions

**Symptom.** Test output includes lines like:

```
[ProcessSuspension] 0x... - ProcessAssertion::acquireSync Failed to
acquire RBS assertion 'XPCConnectionTerminationWatchdog' for process
with PID=... (target is not running or doesn't have entitlement
com.apple.runningboard.assertions.webkit ...)
```

**Why it's harmless.** macOS' RunningBoard tries to assert on the
WebKit content process during tests, but the test runner doesn't have
the entitlement. The WebView used by tests *does* still work; this is
just noisy diagnostic. We've never seen it cause a test failure.

**Fix.** None. If this ever blocks CI, the workaround is to skip
WKWebView-instantiating tests in the test plan.

---

## SQLite migration warning on Swift 6 mode

**Symptom.** Build warning:
`actor-isolated instance method 'execNoSync' can not be referenced
from a nonisolated context; this is an error in the Swift 6 language
mode`.

**Root cause.** `SQLite.init(path:)` ran inside the actor's
non-isolated init context but called the actor-isolated `execNoSync`
helper for the pragma sequence.

**Fix.** [SQLite.swift](../MailClient/Persistence/SQLite.swift) init —
inlined `sqlite3_exec` directly for the bootstrap pragmas, leaving the
isolated `execNoSync` for runtime callers.

---

## File system paths the app touches

For when something refuses to migrate or you need to wipe local state
during testing:

- **SQLite cache** — `~/Library/Application Support/MailStream/mailstream.sqlite`
  (also `-wal`, `-shm`)
- **Account JSON (legacy fallback)** — `~/Library/Application
  Support/MailClient/accounts.json`
- **Keychain credentials** — service `com.mailstrea.app`, account =
  account UUID string. View with `security find-generic-password`.
- **`@AppStorage` defaults** — domain `com.mailstrea.app` in
  `~/Library/Preferences/`. Useful keys:
  - `mailclient.language`
  - `mailclient.list.density`
  - `mailclient.layout.listWidth`
  - `mailclient.detail.loadRemoteImages`
  - `mailclient.notifications.enabled`

To reset everything for a test:

```bash
rm -rf "$HOME/Library/Application Support/MailStream"
rm -rf "$HOME/Library/Application Support/MailClient"
defaults delete com.mailstrea.app
security delete-generic-password -s com.mailstrea.app  # repeat per account
```

---

## HTML body flickers / white-flashes on unrelated UI changes

**Symptom.** Reading an HTML email is fine on first paint, but any
subsequent activity in the window — hovering a sibling button,
selection of a different message, even our own height callback
landing — produces a brief white flash and re-loaded images. With
remote-image-heavy newsletters the flash is severe.

**Root cause.** `HTMLMessageBodyView.updateNSView` was calling
`view.loadHTMLString(wrapped, baseURL: nil)` unconditionally. SwiftUI
calls `updateNSView` on **every** ancestor re-render, not only when
this view's own props change. WKWebView's `loadHTMLString` always
discards the current document and starts fresh — that's the white
flash. Once the new document parses, all `<img>` tags re-resolve from
zero, the height reporter fires, our `@State contentHeight` updates,
SwiftUI re-renders, `updateNSView` fires again. Loop.

**Fix.** [HTMLMessageBodyView.swift](../MailClient/Features/MessageDetail/HTMLMessageBodyView.swift)

- `Coordinator` gained `var lastLoadedHTML: String?`.
- `updateNSView` computes `wrapped` exactly as before, then early-
  returns when `wrapped == coordinator.lastLoadedHTML`. Internal-scroll
  cleanup also moved inside the `loadHTMLString` branch since AppKit
  only rebuilds subviews on actual document loads.
- `coordinator.parent = self` at the top of every `updateNSView` so
  the height callback closure invokes the *current* SwiftUI state
  setters rather than a stale snapshot.

**Detection.** Manual: open any HTML email, hover an unrelated UI
element, observe no flash. Regression test would need a
WKWebView-instantiating fixture which Swift Testing doesn't run
without a host app — TODO.

---

## Mojibake folder names from QQ Mail (`&UXZO1mWHTvZZOQ-`)

**Symptom.** After live-syncing a QQ Mail account, the sidebar
shows folders with names like `&UXZO1mWHTvZZOQ-` instead of `其他文件夹`.
The `roleForAttributes` matcher's localized name fallbacks
(`已发送`, `垃圾邮件`, …) silently fail to fire because the input
they receive is the encoded form, not the decoded one.

**Root cause.** RFC 3501 §5.1.3 specifies that IMAP mailbox names are
in **modified UTF-7** (a.k.a. IMAP-UTF7), not UTF-8. The encoding has
two quirks vs. the standard UTF-7 codec Foundation ships:

1. `&` is the shift character (instead of `+`).
2. The base64 alphabet substitutes `,` for `/`, and there is no `=`
   padding.

`String(data:encoding:)` doesn't have an IMAP-UTF7 codec, and the
`.utf7` codec it does have for plain UTF-7 produces wrong output.
The path was emitting the wire bytes verbatim into `RemoteFolder.name`.

**Fix.** [IMAPResponseParser.swift](../MailClient/Services/Providers/IMAPResponseParser.swift)
gained `decodeMailboxName(_:)`:

- Walks the input character by character.
- Treats `&-` as a literal `&`.
- For every `&...-` run, replaces `,` with `/`, pads to a multiple of
  4 with `=`, base64-decodes, interprets as UTF-16BE, appends.
- Falls back to "emit raw run" if a payload is malformed — never
  hides a folder.

Crucially, `GenericIMAPAdapter.listFolders` keeps the **original**
encoded name on `RemoteFolder.remoteID` so subsequent
`SELECT`/`EXAMINE` calls byte-round-trip the wire form. Only
`RemoteFolder.name` (UI) and the input to `roleForAttributes` go
through the decoder.

**Detection.** [IMAPResponseParserTests.swift](../MailClient/Tests/IMAPResponseParserTests.swift)
covers ASCII passthrough, `&-` literal, single Chinese folder
(`&XfJT0ZAB-` → `已发送`), real QQ folder
(`&UXZO1mWHTvZZOQ-` → `其他文件夹`), mixed ASCII / encoded with
sub-folder delimiters, and malformed payload tolerance. Live
[`IMAPLiveSmokeTests`](../MailClient/Tests/IMAPLiveSmokeTests.swift)
prints the decoded folder list each run.

---

## Build / test commands

```bash
# Regenerate Xcode project after editing project.yml or adding files
make generate

# Build only
xcodebuild -project MailClient.xcodeproj -scheme MailClient \
  -configuration Debug build

# Run tests
xcodebuild -project MailClient.xcodeproj -scheme MailClient \
  -configuration Debug test

# Build a DMG locally
make package          # equivalent to ./scripts/build_dmg.sh
```
