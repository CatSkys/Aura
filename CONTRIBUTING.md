# Contributing

This is a small, mostly-solo project, reviewed the same way it's written. Contributions are welcome, but a few things make one land faster.

## Before writing code

For anything beyond a small fix, open an issue first describing what you want to change and why. It saves a rewritten pull request later if the direction doesn't fit.

## New features: off until someone turns them on

Search stays small by default. Anything new that changes how the browser
looks or behaves — spaces, groups, a visible address bar, a new panel — is:

- **minimal**: the smallest version that does the job, in the app's own quiet style;
- **optional, and off by default**: someone who never asks for it never sees it;
- **findable**: a switch in Settings, and a mention in the welcome screens if it's a big one, so people know it's there to turn on.

Fixes and things every browser is expected to do (Tab moving between a form's fields, ⌘1–⌘9) don't need a switch. Before building a bigger feature, look at how other browsers do it and read what people asked for on its issue; [ROADMAP.md](ROADMAP.md) lists where each request came from.

## Where things are tracked

- [ROADMAP.md](ROADMAP.md), live at [github.com/CatSkys/Aura/blob/main/ROADMAP.md](https://github.com/CatSkys/Aura/blob/main/ROADMAP.md): every idea and report, from issues, pull requests, emails and X, with where it stands — being built, in the next version, next, or not planned. Maintainers keep it with `./ideas`.
- [CHANGELOG.md](CHANGELOG.md): what has changed since the last version. A pull request that fixes or adds something also adds its line under **Unreleased** (and takes its item off the roadmap), so the next update's notes write themselves.

## What tends to get merged

- **Small, focused changes.** One thing per pull request, easy to read start to finish.
- **No new dependencies.** The whole point of this app is staying small; a browser this size doesn't need a package for something Foundation or WebKit already does.
- **Matches the existing style.** Comments here explain *why*, not *what the next line does* — read a couple of existing files before adding a new one. No force-unwraps on anything that can plausibly fail (a network response, a file read, a keychain lookup).
- **Builds clean.** `swift build` with zero warnings you introduced.

## What doesn't

- Rewrites of things that already work, for style reasons alone.
- Anything that phones home, adds analytics, or changes what leaves the app over the network — see the the [README](README.md) for what that boundary currently is.
- Vendoring Chromium or any other engine. This is a WebKit browser on purpose.
- A real key or token anywhere: in code, a test, an issue, a pull request or a pasted log. Tests use keys that are obviously made up. `gitleaks git --pre-commit --staged` with the repo's `.gitleaks.toml` catches most of them before a commit; it is worth running as a pre-commit hook.

## Review

Pull requests are reviewed by Drice, usually with Claude Code doing a first pass on the diff before a human look. That means a review can be fast even when nobody's watching the repo in real time, but it isn't a guarantee of a same-day answer — this isn't anyone's full-time job. Pinging a stale PR after a couple of weeks is completely fine.

## Reporting a bug

Open an issue with: what you did, what you expected, what happened instead, and your macOS version. A crash log, if there is one, lives at `~/Library/Application Support/Aura/crash.log` — it only ever stays on your Mac unless you paste it into the issue yourself.

## Translations

The app is written in English and the English is the key: `Resources/<language>.lproj/Localizable.strings` maps a sentence to the same sentence in another language, and a sentence it doesn't have shows in English rather than not at all. macOS picks the language from the Mac's own order, out of the folders under `Resources/` — adding `zh-Hant.lproj` next to `zh-Hans.lproj` offers 繁體中文 with no code change anywhere.

Two ways a sentence reaches the table, and no third:

- A view SwiftUI makes from a literal — `Text("…")`, `Button("…")`, `Label("…")`, `Toggle("…")` — looks it up itself; nothing is done to it. One with a value in it is written `Text(Localized("Search \(version) is downloading…"))`, so the key is its shape rather than the sentence of the moment.
- Anything that builds its own sentence — the shared views (`Line`, `Pill`, `Caption`, `Nothing`, `Quick`, `Plate`, `Hunt`), `announce`, AppKit's titles and alerts — goes through `Localized(…)`, or `.localized` when what it has is already a `String`. Both live in `Sources/Aura/Localized.swift`.

A value in a sentence is `{1}`, `{2}` in the table, and a translation may move it, leave it out, or use it twice:

```
"Search {1} is downloading…" = "Search 正在下载 {1}…";
"{1} is back" = "{1} 回来了";
```

`./Tools/i18n.py missing` lists the keys a language hasn't covered yet, `./Tools/i18n.py scan` prints every key with the file and line it came from, and `./Tools/i18n.py check` fails when something is missing. Run `plutil -lint Resources/*/Localizable.strings` before sending a pull request; a stray quote in a long sentence is the usual mistake.
