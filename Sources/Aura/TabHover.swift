import AppKit
import SwiftUI

// The card a tab shows when the pointer rests on it: the page's name over the
// site it is on, and four doors — pin it, copy its address, put it beside the
// page on screen, ask about it.
//
// It is Dia's card, read off Dia's own tab hover: the same shape (the name,
// the site under it, one row of doors), the same four places to go. The door
// Dia gives a bookmark is Copy Link here: bookmarks are a page of their own in
// this browser, and what a card about a tab you are not on is wanted for is
// its address — taken without leaving the page you are reading. A pin that has
// wandered off the page it was pinned at gets the way back there in the first
// door, as Dia's does.
//
// It stands beside the column, or under the strip across the top, drawn over
// the page rather than inside the column — the column is 236 points narrower
// than a card. It comes up once the pointer has rested a moment, growing out of
// the edge of its tab, and goes when the pointer leaves both it and its tab,
// with the grace a hand needs to cross the gap between them. Walking the
// column with a card already out, it comes again twice as quickly, and the row
// it speaks for stays lit while the card is the thing being read.

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
    /// How long it takes to come up again when the pointer is walking the
    /// column with a card already out — long enough not to flash a card at
    /// every row crossed, short enough to follow the hand.
    static let wander: TimeInterval = 0.22
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
        // A tab being carried: the rows it passes are not being looked at.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let key = ObjectIdentifier(browser)
        cancel(&going, key)
        cancel(&coming, key)
        let id = tab.id
        // A card that is up is about the tab the pointer has just left: it
        // goes now, rather than standing over another tab's row for the
        // while it takes the pointer to settle.
        let walking = browser.tabCard != nil && browser.tabCard != id
        if walking { withAnimation(Motion.quick) { browser.tabCard = nil } }
        let work = DispatchWorkItem { [weak browser] in
            MainActor.assumeIsolated {
                coming[key] = nil
                guard let browser, browser.tabs.contains(where: { $0.id == id }) else { return }
                onCard.remove(key)
                guard browser.tabCard != id else { return }
                withAnimation(Motion.settle) { browser.tabCard = id }
            }
        }
        coming[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (walking ? wander : pause), execute: work)
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
        guard browser.tabCard != nil else { return }
        withAnimation(Motion.quick) { browser.tabCard = nil }
    }

    private static func putAway(_ browser: Browser, _ key: ObjectIdentifier) {
        guard browser.tabCard != nil else { return }
        cancel(&going, key)
        let work = DispatchWorkItem { [weak browser] in
            MainActor.assumeIsolated {
                going[key] = nil
                guard let browser, !onCard.contains(key), browser.tabCard != nil else { return }
                withAnimation(Motion.quick) { browser.tabCard = nil }
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
            door("link", help: "Copy Link", on: tab.isWeb) {
                browser.copyAddress(of: tab)
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
                .animation(Motion.quick, value: over)
        }
        .buttonStyle(Press(dip: Motion.dipSmall))
        .disabled(!on)
        .onHover { over = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// The symbol here used to have a press style of its own: it was one of the few
// presses in the app, and the only one written by hand. It is Press now, with
// the smaller dip a square that size wants (see Press.swift).

// MARK: - where it stands

/// The card over the window, placed from the room its tab takes (see
/// TabCardAnchorKey and App): beside the column, or under the strip.
struct TabCardOverlay: View {
    @ObservedObject var browser: Browser
    /// The card's own size, measured: beside the column it ends as tall as it
    /// is drawn, and the column's edge says only where it starts.
    @State private var size: CGSize = .zero
    /// Whether this card has come in. It is drawn only once it has been
    /// measured — placed by a size it hasn't got yet, it would slide into place
    /// from somewhere else — and then it grows out of its tab's edge.
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            if let id = browser.tabCard, let tab = browser.tabs.first(where: { $0.id == id }) {
                let spot = spot(in: geo.size)
                card(for: tab)
                    .offset(x: spot.x, y: spot.y)
                    .scaleEffect(shown ? 1 : 0.96, anchor: from)
                    .opacity(shown ? 1 : 0)
                    .animation(Motion.settle, value: shown)
                    // Put away with a fade rather than a snap: the pointer may
                    // be halfway to it, and a card that blinks out reads as a
                    // flicker of the page behind it.
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onPreferenceChange(TabCardSize.self) { measured in
            MainActor.assumeIsolated {
                if size != measured { size = measured }
                if measured.height > 0, !shown { withAnimation(Motion.settle) { shown = true } }
            }
        }
        .onChange(of: browser.tabCard) { _, id in
            // The tab went — ⌘W, or the space changed under it: its card goes
            // with it.
            if let id, !browser.tabs.contains(where: { $0.id == id }) { TabHover.dismiss(browser) }
            // The next card comes in afresh, measured from nothing — and after
            // this one has finished going, so its fade isn't cut short.
            guard id == nil else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    shown = false
                    size = .zero
                }
            }
        }
    }

    /// The edge it grows out of: the one nearest its tab.
    private var from: UnitPoint {
        guard browser.tabCardAnchor.beside else { return .top }
        return browser.prefs.sidePosition == .left ? .leading : .trailing
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
