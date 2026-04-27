# Documentation Index

Start here. Everything in this folder is markdown, hand-written, kept
in lockstep with the code on `main`.

| File | Purpose | Update cadence |
| ---- | ------- | -------------- |
| [`architecture.md`](./architecture.md) | Layered topology, module rules, data flow, schema overview | When the layering changes |
| [`roadmap.md`](./roadmap.md) | Phases, current focus, decision log | Every phase boundary |
| [`phases.md`](./phases.md) | Per-feature status table (F1, F2, …) | Every feature lands |
| [`devlog.md`](./devlog.md) | Dated narrative of what shipped each session | Every working session |
| [`troubleshooting.md`](./troubleshooting.md) | Catalogue of bugs hit, root cause, fix | Every non-trivial bug fix |
| [`conventions.md`](./conventions.md) | Code style, naming, layout, definition-of-done | When a new convention emerges |
| [`dependencies.md`](./dependencies.md) | Library evaluation: what we use / reject / will adopt | Per dep change |
| [`qqmail_imap_probe.py`](./qqmail_imap_probe.py) | Read-only QQ Mail IMAP probe — used to verify what data we can fetch | Standalone tool |

## Reading order for a new contributor

1. **`architecture.md`** — get the mental model in 10 minutes.
2. **`conventions.md`** — know what your patches should look like.
3. **`roadmap.md`** — know what we're building and why.
4. **`devlog.md`** (latest 2–3 entries) — know what just happened.
5. Then read the code, starting at `MailClient/App/MailClientApp.swift`.

## Reading order for a returning contributor

1. **`devlog.md`** — what landed since you were last here.
2. **`roadmap.md`** — what's next.
3. Skim **`troubleshooting.md`** before debugging anything — your bug
   may already have a fix.

## Maintenance rules

- Every file declares its update cadence in its header.
- When in doubt, update the doc *before* the PR is reviewed — not
  after. Half the value of these docs is that they match `main`.
- Don't duplicate facts. If something is in `architecture.md`, link to
  it; don't restate it in `roadmap.md`.
- Keep diagrams ASCII unless visual layout actually matters.
