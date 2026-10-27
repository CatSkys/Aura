import AppKit

// What a right-click on the column offers, as Arc's sidebar menu has one: the
// space on screen, and what can be done to it.
//
// The column's ground is a real view (DragStrip, in Stage.swift) — the window
// is dragged by it — so a context menu on that ground never sees the
// right-click, and the empty room under the rows answered one with nothing at
// all. The menu is AppKit's for that reason, and the space's own dot hangs
// the same one: a right-click anywhere on the column's own ground is about the
// space you are in.
//
// What a space can be given is what Aura has: an icon, a name, a colour, and
// its deletion. The icon and the colour are chosen on the card the dot opens
// (see SpaceSwitcher), so those two rows open the card on the page they
// belong to rather than drawing a second picker of their own.

@MainActor
enum SideMenu {
    /// The column's menu: the space on screen — or, with spaces turned off,
    /// the one thing an empty column can be asked for.
    static func menu(for browser: Browser) -> NSMenu {
        let menu = NSMenu()
        // Every row says for itself whether it may be pressed: without this,
        // AppKit asks the responder chain, which knows none of them.
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem("New Tab") { browser.newTab() })
        guard browser.prefs.usesSpaces else { return menu }
        let space = browser.space
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Change Space Icon…") { browser.openSpaceCard(.icons) })
        menu.addItem(ClosureMenuItem(Localized("Rename “\(space.name)”…")) {
            browser.askRenameSpace(space.id)
        })
        menu.addItem(ClosureMenuItem("Edit Theme Colour…") { browser.openSpaceCard(.colour) })
        menu.addItem(.separator())
        // The card the dot opens: every space, and the one on screen's own
        // settings — the nearest Aura has to Arc's Manage Spaces.
        menu.addItem(ClosureMenuItem("Manage Spaces…") { browser.openSpaceCard(.spaces) })
        // The profile's first space is where everything was before there
        // were spaces, and it stays (see Browser.deleteSpace).
        if space.id != browser.homeSpaceID {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(Localized("Delete “\(space.name)”…")) {
                browser.askDeleteSpace(space.id)
            })
        }
        return menu
    }
}

extension Browser {
    /// The space's card, on the page a menu asked for: the list of spaces
    /// itself, its icons, or its colour (see SpaceSwitcher).
    func openSpaceCard(_ page: SpaceCardPage) {
        spaceCardPage = page
        spaceCardUp = true
    }
}
