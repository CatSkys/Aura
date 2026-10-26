import AppKit
import SwiftUI

// The card a tab shows when the pointer rests on it: the page's name over the
// site it is on, and four doors — pin it, open the page's own settings, put it
// beside the page on screen, ask about it.
//
// It is Dia's card, read off Dia's own tab hover: the same shape (the name,
// the site under it, one row of doors), the same four places to go. The door
// Dia gives a bookmark wears this browser's page settings instead, because the
// things a bookmark would save are already the page's own settings here, and
// they are what the pointer is on. A pin that has wandered off the page it was
// pinned at gets the way back there in the first door, as Dia's does.
//
// It stands beside the column, or under the strip across the top, drawn over
// the page rather than inside the column — the column is 236 points narrower
// than a card. It comes up once the pointer has rested a moment, and goes when
// the pointer leaves both it and its tab, with the grace a hand needs to cross
// the gap between them.

/// Where a tab stands in the window, and which way its card leaves it: beside
/// the column, or under the strip. The tab reports it while the pointer is on
/// it; App's overlay places the card from it.
struct TabCardAnchor: Equatable {
    var frame: CGRect = .zero
    var beside = true
}

/// The room the tab under the pointer takes. The last one with any room in it
/// stands — the pointer crossing to the card leaves its tab behind, and the
/// card has to stay where it was put.
struct TabCardAnchorKey: PreferenceKey {
    static let defaultValue = TabCardAnchor()
    static func reduce(value: inout TabCardAnchor, nextValue: () -> TabCardAnchor) {
        let next = nextValue()
        if next.frame.width > 0 { value = next }
    }
}

/// When the card comes up, and goes away. One window's own, since a pointer is
/// in one window at a time and two windows can be reached in turn.
@MainActor
enum TabHover {
    /// How long the pointer rests on a tab before its card comes up.
    static let pause: TimeInterval = 0.45
    /// How long the card waits after the pointer leaves its tab, for a hand
    /// crossing to the card itself.
    static let grace: TimeInterval = 0.3

    private static var coming: [ObjectIdentifier: DispatchWorkItem] = [:]
    private static var going: [ObjectIdentifier: DispatchWorkItem] = [:]
    /// The windows whose card the pointer is on: that card stays, wherever its
    /// tab is.
    private static var onCard: Set<ObjectIdentifier> = []

    /// The pointer came to a tab: its card in a moment, unless it goes again.
    static func rest(on tab: Tab, in browser: Browser) {
        // A script's sweep walks the row's own hover answers a frame at a
        // time; a card at each is not what that measures (see hoversweep).
        guard !Bench.sweeping else { return }
        let key = ObjectIdentifier(browser)
        cancel(&going, key)
        cancel(&coming, key)
        let id = tab.id
        // A card that is up is about the tab the pointer has just left: it
        // goes now, rather than standing over another tab's row for the
        // while it takes the pointer to settle.
        if let up = browser.tabCard, up != id { browser.tabCard = nil }
        let work = DispatchWorkItem { [weak browser] in
            MainActor.assumeIsolated {
                coming[key] = nil
                guard let browser, browser.tabs.contains(where: { $0.id == id }) else { return }
                onCard.remove(key)
                if browser.tabCard != id { browser.tabCard = id }
            }
        }
        coming[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pause, execute: work)
    }

    /// The pointer left a tab: its card goes, unless the hand is on the card.
    static func leave(_ tab: Tab, in browser: Browser) {
        let key = ObjectIdentifier(browser)
        cancel(&coming, key)
        guard browser.tabCard == tab.id, !onCard.contains(key) else { return }
        putAway(browser, key)
    }

    /// The pointer on the card itself, or off it. The card holds while it is
    /// on it, and goes when it leaves, unless it is back on the tab by then.
    static func card(_ inside: Bool, in browser: Browser) {
        let key = ObjectIdentifier(browser)
        if inside {
            onCard.insert(key)
            cancel(&going, key)
        } else {
            onCard.remove(key)
            putAway(browser, key)
        }
    }

    /// The card of the window put away at once, as a door of it is used.
    static func dismiss(_ browser: Browser) {
        let key = ObjectIdentifier(browser)
        onCard.remove(key)
        cancel(&coming, key)
        cancel(&going, key)
        if browser.tabCard != nil { browser.tabCard = nil }
    }

    private static func putAway(_ browser: Browser, _ key: ObjectIdentifier) {
        guard browser.tabCard != nil else { return }
        cancel(&going, key)
        let work = DispatchWorkItem { [weak browser] in
            MainActor.assumeIsolated {
                going[key] = nil
                guard let browser, !onCard.contains(key) else { return }
                if browser.tabCard != nil { browser.tabCard = nil }
            }
        }
        going[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: work)
    }

    private static func cancel(_ timers: inout [ObjectIdentifier: DispatchWorkItem], _ key: ObjectIdentifier) {
        timers.removeValue(forKey: key)?.cancel()
    }
}

// MARK: - the card

/// The card itself: the name, the site, and the four doors. Dia's shape, in
/// this window's colours: the page's name in the ink of a title, the site a
/// step down in grey, and the doors under them on one line.
struct TabHoverCard: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    /// Put away, once a door has been used.
    let close: () -> Void

    static let width: CGFloat = 236
    static let radius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tab.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let site {
                Text(site)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 3)
            }
            doors
                .padding(.top, 12)
                .padding(.horizontal, -6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 10)
        .frame(width: Self.width, alignment: .leading)
    }

    /// The site as a person says it, without the www: the same line the card
    /// under the address carries (see SiteCard.site).
    private var site: String? {
        tab.pageAddress.map(SiteCard.site)
    }

    // MARK: - the doors

    private var doors: some View {
        HStack(spacing: 0) {
            pinned
            door("slider.horizontal.3", help: "Page Settings", on: canShowSettings) {
                pageSettings()
            }
            door("rectangle.split.2x1", help: "Open in Split View", on: browser.prefs.splitView && !tab.bench) {
                browser.openInSplit(tab)
            }
            door("bubble.left", help: "Ask About This Page…", on: tab.isWeb) {
                if browser.activeID != tab.id { browser.select(tab) }
                browser.askAboutPage()
            }
        }
    }

    /// The pin's door: the way back to a pin that has wandered, unpinning it,
    /// or pinning it.
    @ViewBuilder private var pinned: some View {
        if let home = tab.home, tab.pin != nil, !Browser.samePage(home, tab.address) {
            door("arrow.uturn.backward", help: "Back to Pinned Page") { browser.goHome(tab) }
        } else if tab.pin != nil {
            door("pin.slash", help: "Unpin Tab") { browser.unpin(tab) }
        } else {
            door("pin", help: "Pin Tab", on: tab.isWeb && !tab.shy) { browser.pin(tab) }
        }
    }

    /// A page of the window's own can say what its settings are: the card
    /// under its address, with the zoom, the sound, the darkening and the
    /// rest. A pin's address is the pin's own, a blank tab has no page.
    private var canShowSettings: Bool {
        !tab.isBlank && tab.address != nil && tab.pin == nil
    }

    /// The site's card, as a click on the tab you are on shows it: brought
    /// forward, and its address opened to put the card under (see
    /// beginTabEdit). The same two steps TabMenu's Site Information… takes.
    private func pageSettings() {
        if browser.activeID != tab.id { browser.select(tab) }
        browser.beginTabEdit(tab)
    }

    private func door(_ symbol: String, help: String, on: Bool = true,
                      act: @escaping () -> Void) -> some View {
        CardDoor(symbol: symbol, help: help.localized, on: on) {
            act()
            close()
        }
    }
}

/// One door of the card: its symbol, a wash under the pointer, and nothing
/// else — as the four are in Dia's.
private struct CardDoor: View {
    let symbol: String
    let help: String
    var on = true
    let act: () -> Void

    @State private var over = false

    var body: some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.ink.opacity(on ? 0.72 : 0.22))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(over && on ? Palette.rowHover : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .onHover { over = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - where it stands

/// The card over the window, placed from the room its tab takes (see
/// TabCardAnchorKey and App): beside the column, or under the strip.
struct TabCardOverlay: View {
    @ObservedObject var browser: Browser
    /// The card's own size, measured: beside the column it ends as tall as it
    /// is drawn, and the column's edge says only where it starts.
    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            if let id = browser.tabCard, let tab = browser.tabs.first(where: { $0.id == id }) {
                let spot = spot(in: geo.size)
                card(for: tab)
                    .offset(x: spot.x, y: spot.y)
                    // The first pass has no size to place it by: a moment
                    // later, rather than a card somewhere wrong.
                    .opacity(size.height > 0 ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onPreferenceChange(TabCardSize.self) { measured in
            MainActor.assumeIsolated {
                if size != measured { size = measured }
            }
        }
    }

    /// The system's own liquid glass, as the card of spaces is made (see
    /// SpaceCardOverlay); before it, the window's glass over the page.
    @ViewBuilder
    private func card(for tab: Tab) -> some View {
        let shape = RoundedRectangle(cornerRadius: TabHoverCard.radius, style: .continuous)
        let content = TabHoverCard(browser: browser, tab: tab) { TabHover.dismiss(browser) }
            .background(GeometryReader { box in
                Color.clear.preference(key: TabCardSize.self, value: box.size)
            })
            .fixedSize()
            .onHover { TabHover.card($0, in: browser) }
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: .black.opacity(0.20), radius: 22, y: 8)
        } else {
            content
                .background {
                    CardGlass(theme: browser.space.spaceTheme, radius: TabHoverCard.radius)
                        .clipShape(shape)
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
                .shadow(color: .black.opacity(0.18), radius: 20, y: 7)
        }
    }

    /// Where the card's top-left corner goes, in the window's own points. Out
    /// of the column and clear of it, or under the strip; and kept on the
    /// window, so a tab near an edge has its card whole.
    private func spot(in room: CGSize) -> CGPoint {
        let anchor = browser.tabCardAnchor.frame
        let gap: CGFloat = 8
        var x: CGFloat
        var y: CGFloat
        if browser.tabCardAnchor.beside {
            x = browser.prefs.sidePosition == .left ? anchor.maxX + gap : anchor.minX - gap - size.width
            y = anchor.midY - size.height / 2
        } else {
            x = anchor.minX
            y = anchor.maxY + gap
        }
        x = min(max(x, 8), max(8, room.width - size.width - 8))
        y = min(max(y, 8), max(8, room.height - size.height - 8))
        return CGPoint(x: x, y: y)
    }
}

/// How big the card came out, for the overlay that places it.
private struct TabCardSize: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
