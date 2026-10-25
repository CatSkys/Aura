# Aura

A small, fast, quiet web browser for the Mac — a fork of [Search](https://github.com/driceroland/Search) by [Office Commun](https://officecommun.com), with a full Simplified Chinese interface of its own.

![Aura, with its tabs down the left and a page taking the rest of the window](.github/screenshot.png)

macOS 14 or later · about 7 MB

---

## What it is

Aura is the browser with nothing in the way, in Chinese. A row of tabs — across the top or down the left, your choice — and the page. No toolbar, no start page, no sidebar of suggestions, no account to sign into. One field for addresses and searches, and you are on the page.

It uses **WebKit**, the engine already inside every Mac — the one Safari runs on. That is why the whole app is a few megabytes and opens instantly: there is no second copy of Chromium to download, update and keep in memory.

**What this fork changes.** Search's interface is English. Aura's is English and 简体中文, chosen by the Mac's own language order, with the English kept as the key so a sentence with no translation yet shows in English rather than as a blank. It has its own app identity (`com.catskys.aura`), its own update source and its own issue tracker. Everything else — the features below, the code they are written in — comes from upstream.

## What it does

- **One field.** Type an address and you go there; type words and you search. It finishes addresses from your own history and sends nothing anywhere until you press Return.
- **Tabs that stay out of the way.** Pin the pages you keep open all day and they shrink to a letter or their icon. Tabs from your last session come back instantly and cost nothing until you click them. `⌘K` lists your open tabs by name.
- **Two pages side by side.** Turn Split View on in Settings › Tabs, then drag a tab onto a page or choose Tabs › Split Current Page.
- **Reading mode.** `⇧⌘R` strips a page down to the article.
- **Hide anything, for good.** `⇧⌘H`, then click a cookie banner or a newsletter overlay — it is gone, and it is still gone on that site next time, before the page has drawn.
- **An ad blocker that runs before the page.** EasyList and EasyPrivacy — what a real blocker is made of — converted at build time into WebKit's own block list, so an advert or a tracker is refused before the request is made and the box it leaves is hidden before the page draws. On by default; a site can be brought down to blocking alone, or off, in Settings › Privacy. A site that checks whether a blocker is here is answered by the lists' own scriptlets, run before the page's first script.
- **Video that follows you.** `⇧⌘P` lifts the video out of the page into a small window above everything.
- **Passwords, in your keychain.** Offered under the field once a sign-in has actually worked — never filled in on its own. Bring yours in from Chrome, Arc, Dia, Brave, Firefox, Edge or Safari's export; nothing leaves the Mac.
- **Light, dark, or the Mac's own**, and the Chinese interface follows the Mac too.
- **Chrome extensions, without Chrome.** Paste a Chrome Web Store link in Settings › Extensions, or load an unpacked folder. They run on WebKit's own extension engine, with the APIs it lacks filled in. macOS 15.4 or later.

## Build it

```bash
git clone https://github.com/CatSkys/Aura.git
cd Aura
./build.sh                    # build/Aura.app, ad-hoc signed, runs here
./build.sh release dmg        # + build/Aura.dmg, Aura.zip and appcast.json
```

`swift build` alone compiles the binary; `./build.sh` is what wraps it in an app bundle, with the icon, the AppleScript dictionary and the translations where macOS looks for them. `AURA_ARCH=x86_64 ./build.sh release` makes the Intel build.

`./build.sh release ship` notarises and staples, and needs a Developer ID in the keychain and a notarytool profile — see the top of the script.

## Translations

English is the key. `Resources/zh-Hans.lproj/Localizable.strings` says what each sentence is in Chinese, and a `zh-Hant.lproj` folder beside it would offer 繁體中文 with no code change anywhere.

```bash
./Tools/i18n.py scan      # every key, by file and line
./Tools/i18n.py missing   # what a language hasn't covered yet
./Tools/i18n.py check     # the same, for a build to fail on
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for how a sentence reaches the table, and for what tends to get merged.

The mark is `Icon/mark.svg`; `./Tools/mark.py Icon/mark.svg` writes the path the app draws into `Sources/Aura/AuraMark.swift`, with arc commands turned into cubics. The app icon is `Icon/AppIcon.png` — 1024 points square, corners rounded — and every size `build.sh` needs is taken from it.

## Updates and feedback

Aura looks at `https://catskys.github.io/Aura/appcast.json` (or `/Aura/intel/appcast.json` on an Intel Mac) for a newer build and offers it; nothing installs unless you press Install. Bugs and requests go to [the issue tracker](https://github.com/CatSkys/Aura/issues) — Help › Send Feedback fills in the version in an issue for you.

## Licence

MIT, as upstream. See [LICENSE](LICENSE): the copyright of the original work stays with Office Commun, and the changes since the fork are CatSkys's.

[CHANGELOG.md](CHANGELOG.md) and [ROADMAP.md](ROADMAP.md) come from upstream and keep their history; changes made here are marked under **Unreleased**.
