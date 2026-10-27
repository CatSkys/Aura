import SwiftUI

// What's new, once, after an update.
//
// New features start off, so someone who never opens Settings never meets
// them (a reply on X). The first time a newer version opens, a small card
// shows its new switches, each with a line of what it does and the switch
// itself, and — so nothing gets lost — the switches from earlier versions
// that are still off. Nothing else: few words (Drice). Closed, it
// doesn't come back for that version. Not after a fresh install: the welcome
// is for that. Every version's notes are in Settings › About › What's New…
//
// A release edits `toggles` (its new switches, marked with its version),
// `releases` (that it has a card) and `notes` (what it brought).

enum WhatsNew {
    /// A switch the card offers: the same setting as in Settings.
    struct Toggle {
        let title: String
        let detail: String
        /// The version it came in.
        let since: String
        let get: @MainActor (Preferences) -> Bool
        let set: @MainActor (Preferences, Bool) -> Void
    }

    /// A version that has a card.
    struct Release {
        let version: String
    }

    /// Every switch worth meeting, oldest last. The card shows this
    /// version's, and the older ones still off.
    static let toggles: [Toggle] = (AI.shipped ? [
        Toggle(title: "AI on pages", detail: "Summarize a page or ask about it. Choose where it runs in Settings › AI.",
               since: "1.0.5", get: { $0.ai }, set: { $0.ai = $1 }),
    ] : []) + [
        Toggle(title: "Suggestions from your search engine", detail: "Searches suggested as you type. What you type is sent to your engine; never from a private tab.",
               since: "1.0.6", get: { $0.engineSuggests }, set: { $0.engineSuggests = $1 }),
        Toggle(title: "Pins keep their site", detail: "Links elsewhere open beside it, and ⌘W takes a pin back to its page, as in Arc.",
               since: "1.0.6", get: { $0.pinsGoHome }, set: { $0.pinsGoHome = $1 }),
        Toggle(title: "Darken light pages", detail: "While Aura is dark, pages with no dark look of their own are darkened.",
               since: "1.0.6", get: { $0.darkensPages }, set: { $0.darkensPages = $1 }),
        Toggle(title: "Roomier tabs", detail: "Taller rows and larger titles in the sidebar.",
               since: "1.0.6", get: { $0.roomyTabs }, set: { $0.roomyTabs = $1 }),
        Toggle(title: "New tab in a floating field", detail: "⌘T raises the address field over the page you are on, as in Arc.",
               since: "1.0.6", get: { $0.floatingNewTab }, set: { $0.floatingNewTab = $1 }),

        Toggle(title: "Pinned rows", detail: "Pins as rows with their names, under the squares, as in Arc. Right-click a tab to pin it as a row.",
               since: "1.0.5", get: { $0.listsPins }, set: { $0.listsPins = $1 }),
        Toggle(title: "Start with a fresh window", detail: "Your pinned tabs, tab groups and named tabs, and none of last time's others.",
               since: "1.0.5", get: { $0.startsFresh }, set: { $0.startsFresh = $1 }),

        Toggle(title: "Sidebar on the right", detail: "The tabs down the right edge of the window.",
               since: "1.0.4", get: { $0.sidebar && $0.sidePosition == .right },
               set: { prefs, on in
                   if on { prefs.sidebar = true }
                   prefs.sidePosition = on ? .right : .left
               }),
        Toggle(title: "Videos wait for a click", detail: "Videos don't start by themselves, even without sound.",
               since: "1.0.4", get: { $0.waitsForPlay }, set: { $0.waitsForPlay = $1 }),
        Toggle(title: "Always show the downloads button", detail: "Your downloads one click away, beside the other buttons.",
               since: "1.0.4", get: { $0.alwaysShowsDownloads }, set: { $0.alwaysShowsDownloads = $1 }),

        Toggle(title: "Spaces", detail: "Separate sets of tabs, each with its own sign-ins. ⌃1–⌃9 to switch.",
               since: "1.0.1", get: { $0.usesSpaces }, set: { $0.usesSpaces = $1 }),
        Toggle(title: "A sidebar that hides", detail: "The page takes the whole window; the tabs come out at the edge.",
               since: "1.0.1", get: { $0.sidebar && $0.sideHides },
               set: { prefs, on in
                   if on { prefs.sidebar = true }
                   prefs.sideHides = on
               }),
        Toggle(title: "Bookmarks bar", detail: "Your bookmarks in a row above the page.",
               since: "1.0.2", get: { $0.bookmarksBar }, set: { $0.bookmarksBar = $1 }),
        Toggle(title: "Float the video when you switch apps", detail: "A playing video follows you out into a small window.",
               since: "1.0.2", get: { $0.floatsAway }, set: { prefs, on in if on { prefs.floatOwn = .tabsOrApps } else { prefs.floatsAway = false } }),
        Toggle(title: "Pages at 120 Hz", detail: "Smoother scrolling and animations on screens that can. Uses more battery.",
               since: "1.0.2", get: { $0.fastPages != .never }, set: { $0.fastPages = $1 ? .onPower : .never }),
        Toggle(title: "Scroll with the middle button", detail: "Click the wheel, then move the mouse to scroll, as on Windows.",
               since: "1.0.3", get: { $0.autoScroll }, set: { $0.autoScroll = $1 }),
    ]

    /// Aura's own versions that brought a switch worth a card. 0.1.0 is the
    /// first release and has nothing before it to switch on, so the list
    /// starts empty; a version that brings a new switch adds itself.
    static let releases: [Release] = []

    /// This version's card, when it has one.
    static var current: Release? { releases.first { $0.version == Updater.version } }

    /// Version strings in order: 1.0.10 after 1.0.9.
    static func older(_ one: String, than other: String) -> Bool {
        let a = one.split(separator: ".").compactMap { Int($0) }
        let b = other.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static let seenKey = "whatsnew.seen"

    /// At launch, once: whether the card is due. Not on a fresh install (the
    /// welcome is up, and this version counts as seen), nor in a test world
    /// unless the bench asks; otherwise once per version that has a card.
    @MainActor static func due(prefs: Preferences, welcoming: Bool) -> Bool {
        let store = Store.settings
        guard let current, !Store.testing else { return false }
        if welcoming {
            store.set(current.version, forKey: seenKey)
            return false
        }
        guard store.string(forKey: seenKey) != current.version else { return false }
        store.set(current.version, forKey: seenKey)
        return true
    }

    // MARK: - every version's notes

    /// What a version brought, for Settings › About › What's New…
    struct Notes {
        let version: String
        let date: String
        /// A sentence or two: what the version is about.
        let headline: String
        let new: [String]
        let better: [String]
        let fixed: [String]
    }

    /// Newest first.
    static let notes: [Notes] = [
        Notes(
            version: "0.1.0", date: "25 October 2026",
            headline: "The first version, made for the day Arc stops.",
            new: [
                "Tabs in a row across the top, or down a side as a column; spaces for the different parts of your life; pinned tabs that keep their place, as squares or as rows with their names.",
                "One field for addresses and searches, and the page takes the rest of the window. Settings, history, downloads and a new tab are commands you can type there.",
                "It runs on the WebKit already inside every Mac: it opens at once, weighs about 7 MB, and keeps no second copy of anything in memory.",
                "Chrome extensions from the Chrome Web Store on macOS 15.4 or later, with bookmarks, history, downloads, side panels and offscreen documents filled in where WebKit leaves them out.",
                "Ads and trackers refused before a request is made, and their empty boxes hidden before the first frame — EasyList's, EasyPrivacy's and uBlock Origin's own lists, with the checks sites make for a blocker answered as they want to hear it.",
                "Reading mode, a floating video, profiles with their own sign-ins and history, pages translated on this Mac, and passwords in the keychain.",
                "Every sentence in English and in 简体中文, by the Mac's own language, with the English kept as the key — a sentence no translation has reached yet shows in English rather than as a blank.",
                "No account, no sync, no telemetry: tabs, history and passwords stay on this Mac, and the only things that leave it are the pages you ask for and one request a day to see whether there is a newer version.",
                "Passkeys are not in this version: the entitlement they need is granted to organization accounts only.",
            ],
            better: [],
            fixed: []
        ),
    ]
}

/// The card: what's new in this version, its switches right there, and
/// the earlier ones still off.
struct WhatsNewCard: View {
    let release: WhatsNew.Release
    @ObservedObject var prefs: Preferences
    let close: () -> Void
    let notes: () -> Void

    /// Read once, as the card opens: a switch turned on here stays in the
    /// list rather than vanishing under the hand.
    @State private var earlier: [WhatsNew.Toggle]?

    private var fresh: [WhatsNew.Toggle] { WhatsNew.toggles.filter { $0.since == release.version } }

    var body: some View {
        Plate(Localized("New in Aura \(release.version)"), width: 460, close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rows(fresh)
                    if let earlier, !earlier.isEmpty {
                        Caption("From earlier versions, in case you missed them")
                            .padding(.top, 6)
                        rows(earlier)
                    }
                }
            }
            .frame(maxHeight: 470)
            .fixedSize(horizontal: false, vertical: true)
        } foot: {
            HStack {
                Button(action: notes) {
                    Text("Everything that's new…")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(Press())
                Spacer()
                Pill("Close", filled: true, action: close)
            }
        }
        .onAppear {
            if earlier == nil {
                earlier = WhatsNew.toggles.filter { WhatsNew.older($0.since, than: release.version) && !$0.get(prefs) }
            }
        }
    }

    private func rows(_ toggles: [WhatsNew.Toggle]) -> some View {
        Card {
            ForEach(Array(toggles.enumerated()), id: \.offset) { index, toggle in
                if index > 0 { Rule() }
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toggle.title.localized)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink)
                        Text(toggle.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Switch(on: Binding(get: { toggle.get(prefs) }, set: { toggle.set(prefs, $0) }))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

/// Every version's notes, newest first: Settings › About › What's New…
struct ReleaseNotesPanel: View {
    let close: () -> Void

    var body: some View {
        Plate("What's New", width: 560, close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(WhatsNew.notes, id: \.version) { note in
                        version(note)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .listHeight(480)
        }
    }

    private func version(_ note: WhatsNew.Notes) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Localized("Aura \(note.version)"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if !note.date.isEmpty {
                    Text(note.date)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                }
            }
            Text(note.headline)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            list("New", note.new)
            list("Better", note.better)
            list("Fixed", note.fixed)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.localized)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.faint)
                        Text(line.localized)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12.5))
                }
            }
        }
    }
}
