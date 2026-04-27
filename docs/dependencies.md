# Dependency Strategy

> "Should we use a library for this?" — recurring question. This doc records
> the per-area evaluation so we don't re-debate.

## Guiding principles

1. **Apple-first.** Anything in Foundation / SwiftNIO / CryptoKit /
   SwiftData / SQLite3 we use directly. They ship with the OS, never break,
   and Apple owns the long-term maintenance cost.

2. **Swift Package Manager only.** No CocoaPods, no Carthage. SPM keeps the
   build reproducible and the Xcode project clean.

3. **No transitive C++ bombs.** A pure-Swift dep is cheap; a wrapper around
   a 200 KLoC C++ library (mailcore2, ICU, etc.) brings binary bloat,
   memory-model friction, and signing/notarization headaches.

4. **A library must beat hand-rolled code on all of:** correctness on edge
   cases we haven't seen, time-to-feature, ongoing maintenance load. Two
   out of three is not enough — pulling a dep is itself maintenance.

5. **No abandoned libs.** If the last commit is > 18 months old, treat it
   as a starting point for our own code, not a dependency.

## Current dependency surface

| What | How | Why no library |
| ---- | --- | -------------- |
| SQLite | Direct `import SQLite3` + `Persistence/SQLite.swift` (~250 LOC actor) | GRDB / SQLite.swift would add 5–8 kLOC + their own concurrency model; we only need open / exec / prepare / step / bind / column. Win not worth the cost. |
| MIME parsing | `Core/Utilities/MIMEParser.swift` (~280 LOC) + 7 unit tests | mailcore2 is the only "real" option, and brings C++ + 5–10 MB. Our parser is small, focused, fully tested. |
| POP3 / SMTP | `QQMailService.swift` raw sockets (transitional) | No maintained Swift SMTP/POP library. We replace this with SwiftNIO + NIOIMAP in Phase 3. |
| HTML → text | Regex pass in `MIMEParser.stripHTML` | SwiftSoup would do better but we display, not author HTML. Adequate. |
| Logging | `MailClientLogger` (os.Logger wrapper) | Apple's `os.Logger` is built-in. swift-log adds a façade we don't need yet. |
| Keychain | `MailAccountCredentialsStore` over Security.framework | No real benefit from KeychainAccess libs for our usage. |

**Total external dependencies today: 0.**

## Recommended adoptions (Phase 3, when we add real IMAP / Gmail / Outlook)

These are the libraries that **will actually save us weeks** when the time
comes. They're official Apple / Google / Microsoft, all SPM, all permissive
licenses.

### 🟢 swift-nio-imap (Apple)

- Repo: https://github.com/apple/swift-nio-imap
- License: Apache 2.0
- Why: **Real IMAP protocol** — UID FETCH ranges, IDLE for push, CONDSTORE
  for incremental sync, multi-byte boundary handling. Hand-rolling this
  costs at least 2 weeks plus an indefinite tail of "wait, Yahoo IMAP
  responds with X". Apple uses it in their own products. Stable.
- Pulls in: swift-nio, swift-nio-ssl. ~3 deps total.
- When: when we replace `QQMailService` with `QQMailAdapter` (Phase 3).
- Risk: heavier debug builds; learning NIO if we haven't.

### 🟢 swift-nio + swift-nio-ssl (Apple)

- Already a transitive dep of `swift-nio-imap`.
- Direct value: gives us a proper TLS / async byte-stream substrate for
  SMTP too. Replaces our `SecureMailStreamClient` with channels.
- License: Apache 2.0.

### 🟢 AppAuth-iOS (OpenID Foundation / Google-maintained)

- Repo: https://github.com/openid/AppAuth-iOS
- License: Apache 2.0.
- Why: **Required for Gmail.** Google's OAuth2 flow needs PKCE + custom
  URL scheme handling + token refresh. ASWebAuthenticationSession can
  drive the browser part, but managing the response, token lifetime, and
  refresh is exactly what AppAuth does. Doing it ourselves would mean
  re-implementing RFC 6749 / 7636.
- When: when `GmailAdapter` lands.
- Alternative we could pick instead: roll our own using
  `ASWebAuthenticationSession` + a small token-store helper. Estimated
  cost ~3 days vs. importing AppAuth. **Recommendation: import AppAuth.**

### 🟡 MSAL for macOS (Microsoft)

- Repo: https://github.com/AzureAD/microsoft-authentication-library-for-objc
- License: MIT.
- Why: Outlook / Microsoft 365 uses Microsoft Identity Platform, MSAL is
  Microsoft's blessed flow. Without it, we'd be re-implementing v2 OAuth
  for Microsoft and missing things like work/school account picker UX.
- Caveat: Objective-C library; works fine from Swift but adds an ObjC
  bridging header. Marginally heavier than AppAuth.
- When: when `OutlookAdapter` lands.
- Alternative: also doable with AppAuth — Microsoft just ships MSAL as
  the "official" path. **Recommendation: try AppAuth first** (covers both
  Google and Microsoft); fall back to MSAL only if we hit feature gaps.

### 🟡 SwiftSoup (community)

- Repo: https://github.com/scinfu/SwiftSoup
- License: MIT.
- Why: HTML parsing as a DOM. Our `stripHTML` regex covers the basics,
  but if we ever need:
  - Inline-image rewriting (cid: → on-disk)
  - Quoted-reply collapsing (`<blockquote>` → "Show quoted text")
  - Better preview extraction (skip nav menus, signatures)
  …SwiftSoup is the right tool.
- When: only if HTML rendering becomes a UX priority.
- **Recommendation: defer.** Current text bodies render fine; revisit
  when we get a complaint.

## Evaluated and rejected

| Library | Verdict | Reason |
| ------- | ------- | ------ |
| MailCore2 | ❌ | C++ baggage, ~10 MB binary, last big update 2021, complex memory ownership over the ObjC bridge. |
| Postal (Snipsco) | ❌ | Abandoned (2017). Was a MailCore2 wrapper. |
| Postal (community fork) | ❌ | Same. |
| GRDB.swift | ❌ | Excellent library, but our needs are SELECT/INSERT/UPDATE — our 250-LOC wrapper meets them. Adding GRDB means buying into its query DSL, GRDBQuery, observation layer. |
| SQLite.swift | ❌ | Same logic; we'd use 5% of it. |
| swift-mime / SwiftMime | ❌ | Searched npm-style names; no maintained Swift MIME library exists with the multipart-recursion + charset story we need. We just wrote one. |
| Hummingbird / Vapor | ❌ | Server frameworks; not relevant. |
| KeychainAccess | ❌ | A wrapper around Security.framework; our wrapper is sufficient. |
| swift-crypto | 🟡 maybe | Already covered by CryptoKit on macOS. Useful only if we ever ship Linux server-side code. |
| swift-log | 🟡 maybe | Could replace `MailClientLogger`. Marginal. Wait until logging needs structure. |
| swift-collections | 🟡 maybe | OrderedDictionary etc. — adopt when a feature actually needs it. |
| Sourcery / SwiftFormat | 🟡 dev-only | Worth setting up SwiftFormat in CI when the codebase grows past 20k LOC. Not a runtime dep. |

## Adoption plan (what would actually happen)

When Phase 3 starts:

1. Add SPM block in `project.yml`:

   ```yaml
   packages:
     SwiftNIO:
       url: https://github.com/apple/swift-nio
       from: 2.66.0
     SwiftNIOIMAP:
       url: https://github.com/apple/swift-nio-imap
       from: 0.4.0
     AppAuth:
       url: https://github.com/openid/AppAuth-iOS
       from: 1.7.0
   targets:
     MailClient:
       dependencies:
         - package: SwiftNIO
           product: NIOCore
         - package: SwiftNIO
           product: NIOPosix
         - package: SwiftNIO
           product: NIOSSL
         - package: SwiftNIOIMAP
         - package: AppAuth
           product: AppAuth
   ```

2. Run `make generate` — XcodeGen resolves packages and updates `Package.resolved`.

3. Wire IMAP into `Services/Providers/QQMailAdapter.swift` (new),
   `Services/Providers/GenericIMAPAdapter.swift`, etc.

## Until then

We are not blocked on libraries for the current scope. The path is:

1. Phase 2 — wire SQLite cache through to the UI (no deps).
2. Phase 3 — port `QQMailService` to `QQMailAdapter` using NIOIMAP.
3. Phase 3 — `GmailAdapter` with AppAuth.
4. Phase 3 — `OutlookAdapter` with AppAuth (or MSAL fallback).

Total deps after Phase 3: **3 packages** (NIOIMAP pulls NIO + NIOSSL; AppAuth
is standalone). That's a defensible footprint for a real mail client.
