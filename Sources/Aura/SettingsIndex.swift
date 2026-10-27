import SwiftUI

// Every line of Settings, written down once.
//
// Settings › each section draws its groups from this list, and the ⌘F
// "Find a setting" field filters the same list, so a setting can't be on a
// page and missing from the search, or the other way round. Each line says
// which keys it reads and writes (the bench's `settings` verb answers with
// them, see Tests/settings_layout.py). The controls themselves are drawn in
// Settings.swift; what a merged control does to the old keys is here, on
// Preferences, so the switch and the bench write the same thing.

/// A titled group inside a section: a small heading with its icon, then its
/// rows in one card. The heading is all there is: what a group is for is
/// said by its rows, and anything a row can't say lives behind its (i).
struct SettingsGroup: Identifiable {
    let id: String
    let page: SettingsPanel.Page
    let title: String
    let icon: String
}

/// One row of Settings.
struct SettingsItem: Identifiable {
    enum Kind {
        /// A control on the right of the row.
        case control
        /// A control wide enough to go under the words (pictures, long
        /// segmented choices).
        case wide
        /// No control: a feature that is always there, said so plainly.
        /// Only shown by the find field.
        case note
    }

    let id: String
    let group: String
    let icon: String
    let title: String
    /// One short line, under ~90 characters.
    let detail: String
    /// The rest of the story, behind the (i).
    var more: String? = nil
    /// The defaults keys the row reads and writes.
    var keys: [String] = []
    /// Other words someone might type for it.
    var words: [String] = []
    var kind: Kind = .control
    /// The row it hangs under: indented, and only there while that one
    /// makes it count (see SettingsIndex.applies).
    var parent: String? = nil
    /// Only the find field shows it (moved to a menu, or always on).
    var findOnly = false

    var page: SettingsPanel.Page { SettingsIndex.group(group)?.page ?? .general }
    /// Drawn under its parent, indented, when that is the row above it in
    /// the same group; a row whose parent is elsewhere is only hidden.
    var hangs: Bool { parent.flatMap(SettingsIndex.item)?.group == group }
}

enum SettingsIndex {
    // MARK: - groups

    static let groups: [SettingsGroup] = [
        .init(id: "browser", page: .general, title: "Browser", icon: "globe.desk"),
        .init(id: "downloads", page: .general, title: "Downloads", icon: "arrow.down.circle"),

        .init(id: "theme", page: .appearance, title: "Light and Dark", icon: "circle.lefthalf.filled"),
        .init(id: "window", page: .appearance, title: "Window", icon: "macwindow"),
        .init(id: "tablook", page: .appearance, title: "Tabs", icon: "textformat.size"),
        .init(id: "motion", page: .appearance, title: "Motion", icon: "wind"),

        .init(id: "newtabs", page: .tabs, title: "New Tabs", icon: "plus.square"),
        .init(id: "memory", page: .tabs, title: "Memory", icon: "moon.zzz"),
        .init(id: "tabbar", page: .tabs, title: "Tab Bar", icon: "number"),

        .init(id: "search", page: .browsing, title: "Search", icon: "magnifyingglass"),
        .init(id: "links", page: .browsing, title: "Links", icon: "link"),
        .init(id: "reading", page: .browsing, title: "Reading Mode", icon: "doc.plaintext"),
        .init(id: "video", page: .browsing, title: "Video", icon: "play.rectangle"),
        .init(id: "pages", page: .browsing, title: "Pages", icon: "doc.richtext"),

        .init(id: "arc", page: .spaces, title: "From Arc", icon: "arrow.down.forward.square"),
        .init(id: "spaces", page: .spaces, title: "Spaces and Profiles", icon: "rectangle.3.group"),
        .init(id: "pins", page: .spaces, title: "Pins", icon: "pin"),
        .init(id: "opening", page: .spaces, title: "Opening", icon: "command"),

        .init(id: "passwords", page: .passwords, title: "Passwords", icon: "key"),
        .init(id: "apple", page: .passwords, title: "Apple Passwords", icon: "lock.rectangle.stack"),

        .init(id: "blocking", page: .privacy, title: "Blocking", icon: "shield"),
        .init(id: "permissions", page: .privacy, title: "Site Permissions", icon: "checkmark.shield"),
        .init(id: "clear", page: .privacy, title: "Clear", icon: "trash"),

        .init(id: "mouse", page: .keyboard, title: "Mouse and Trackpad", icon: "computermouse"),

        .init(id: "updates", page: .about, title: "Updates", icon: "arrow.triangle.2.circlepath"),
        .init(id: "developer", page: .about, title: "Developer", icon: "hammer"),
    ]

    static func group(_ id: String) -> SettingsGroup? { groups.first { $0.id == id } }

    /// The colour a group's rows wear. One to a card, and none of a page's
    /// cards wearing another's, so the eye counts the groups down a page
    /// before it reads a word of them: General's two, Appearance's four,
    /// Browsing's five are all different colours. Written out rather than
    /// worked out, so a group keeps the colour it has however the pages
    /// are rearranged later.
    static func tint(of group: String) -> Color {
        switch group {
        case "browser", "tabbar", "search", "pins", "passwords", "mouse", "updates":
            return Palette.tileBlue
        case "downloads", "newtabs", "spaces", "blocking":
            return Palette.tileGreen
        case "theme", "reading", "opening", "developer":
            return Palette.tilePurple
        case "window", "arc":
            return Palette.tileOrange
        case "tablook", "links", "permissions":
            return Palette.tileTeal
        case "motion", "video":
            return Palette.tilePink
        case "memory", "pages", "apple":
            return Palette.tileIndigo
        case "clear":
            return Palette.tileRed
        default:
            return Palette.tileBlue
        }
    }
    static func groups(of page: SettingsPanel.Page) -> [SettingsGroup] { groups.filter { $0.page == page } }
    static func items(in group: String) -> [SettingsItem] { items.filter { $0.group == group && !$0.findOnly } }

    // MARK: - rows

    static let items: [SettingsItem] = [
        // General
        .init(id: "general.default", group: "browser", icon: "link.badge.plus",
              title: "Default browser", detail: "",
              more: "Links in Mail, Slack and the rest open here.",
              words: ["default browser"]),
        .init(id: "general.import", group: "browser", icon: "square.and.arrow.down.on.square",
              title: "Import data", detail: "Bookmarks, history, passwords and extensions",
              more: "From a browser on this Mac, or from a file it exported. Nothing leaves this Mac.",
              words: ["import", "chrome", "safari", "arc", "migrate"]),
        .init(id: "quit.confirm", group: "browser", icon: "power",
              title: "Confirm before quitting", detail: "",
              keys: ["quit.confirm"], words: ["quit", "cmd q"]),
        .init(id: "downloads.folder", group: "downloads", icon: "folder",
              title: "Save to", detail: "", keys: ["downloads"], words: ["download folder"]),
        .init(id: "downloads.ask", group: "downloads", icon: "questionmark.folder",
              title: "Ask where to save each file", detail: "",
              keys: ["downloads.ask"]),
        .init(id: "downloads.button", group: "downloads", icon: "arrow.down.to.line",
              title: "Always show the downloads button", detail: "",
              more: "Off, the button appears only while a download is running.",
              keys: ["downloads.button"]),

        // Appearance
        .init(id: "look", group: "theme", icon: "circle.lefthalf.filled",
              title: "Appearance", detail: "Light, Dark or Auto. Pages follow it",
              keys: ["look"], words: ["dark mode", "light mode", "theme", "system"], kind: .wide),
        .init(id: "pages.dusk", group: "theme", icon: "moon",
              title: "Darken pages that stay light", detail: "",
              more: "Sites with a dark style already follow it. ⇧⌘D for this site, ⌥⇧⌘D to pause everywhere.",
              keys: ["pages.dusk"], words: ["dark", "dusk", "night"], parent: "look"),
        .init(id: "tabs.layout", group: "window", icon: "sidebar.left",
              title: "Tab position", detail: "",
              keys: ["sidebar", "sidebar.position"],
              words: ["sidebar", "vertical tabs", "column", "left", "right", "top", "tab bar", "position"], kind: .wide),
        .init(id: "sidebar.hides", group: "window", icon: "sidebar.squares.left",
              title: "Auto-hide the column", detail: "",
              more: "The page takes the whole window. ⌘S brings the tabs out.",
              keys: ["sidebar.hides"], words: ["auto hide", "sidebar"], parent: "tabs.layout"),
        .init(id: "layout.cards", group: "window", icon: "rectangle.inset.filled",
              title: "Page as a card", detail: "",
              more: "Off, the page reaches the window's edges.",
              keys: ["layout.cards"], words: ["edge to edge", "rounded", "margin"], kind: .wide, parent: "tabs.layout"),
        .init(id: "toolbar.left", group: "window", icon: "arrow.left.arrow.right",
              title: "Back and forward on the left", detail: "",
              keys: ["toolbar.left"], words: ["toolbar", "buttons", "navigation"], parent: "tabs.layout"),
        .init(id: "sidebar.roomy", group: "tablook", icon: "textformat.size.larger",
              title: "Taller tab rows", detail: "",
              keys: ["sidebar.roomy"], words: ["roomier", "bigger", "larger", "text size", "accessibility"], parent: "tabs.layout"),
        .init(id: "glyph", group: "tablook", icon: "character",
              title: "Tabs show", detail: "",
              keys: ["glyph"], words: ["favicon", "icons", "letters"]),
        .init(id: "tabs.reading", group: "tablook", icon: "text.line.first.and.arrowtriangle.forward",
              title: "Reading progress", detail: "",
              more: "The tab you're on fills with grey as you scroll down.",
              keys: ["tabs.reading"], words: ["how far", "progress", "scroll"]),
        .init(id: "tabs.give", group: "tablook", icon: "hand.point.up.left",
              title: "Press feedback", detail: "Buttons and tabs give a little under the click.",
              keys: ["tabs.give"], words: ["pressed", "press", "animation", "bounce", "spring", "motion"]),
        .init(id: "bookmarks.bar", group: "tablook", icon: "bookmark",
              title: "Show the bookmarks bar", detail: "",
              keys: ["bookmarks.bar"], words: ["favorites bar"]),
        .init(id: "bookmarks.off", group: "tablook", icon: "bookmark.slash",
              title: "Bookmarks", detail: "",
              more: "Off, the button, the menu, the list and the bar go. What is kept stays in the file and comes back with this on.",
              keys: ["bookmarks"], words: ["bookmarks off", "favourites"]),
        .init(id: "motion.light", group: "motion", icon: "leaf",
              title: "Reduce motion in Low Power Mode", detail: "",
              more: "On in Low Power Mode, and while the Mac runs hot. Pages are left as they are.",
              keys: [Motion.lightKey], words: ["battery", "animations", "motion"]),

        // Tabs
        .init(id: "tabs.newPlace", group: "newtabs", icon: "arrow.right.to.line",
              title: "New tab position", detail: "",
              more: "After current puts a link beside its tab, and ⌘T's at the end. Pins stay first; a link from a group stays in it.",
              keys: ["tabs.newPlace"], words: ["new tab", "order"]),
        .init(id: "tabs.newAfterLast", group: "newtabs", icon: "plus.rectangle.on.rectangle",
              title: "Leave a new tab when the last one closes", detail: "",
              more: "Otherwise you land on a pinned tab.",
              keys: ["tabs.newAfterLast"], words: ["last tab"]),
        .init(id: "tabs.lazy", group: "newtabs", icon: "hourglass",
              title: "Load background tabs on first visit", detail: "",
              more: "⌘-click, the middle button, and links sent from another app. ⇧⌘-click still opens at once.",
              keys: ["tabs.lazy"], words: ["lazy", "background"]),
        .init(id: "tabs.popupWindows", group: "newtabs", icon: "macwindow.on.rectangle",
              title: "Sized pop-ups in small windows", detail: "",
              more: "A call, a sign-in or a chat asking for a window its size gets one. Pop-up blocking still applies.",
              keys: ["tabs.popupWindows"], words: ["popup", "pop-up", "window"]),
        .init(id: "tabs.sleep", group: "memory", icon: "moon.zzz",
              title: "Sleep unused tabs", detail: "",
              more: "Pinned tabs, sound, calls and anything typed stay awake. Right-click a site's card to keep it awake.",
              keys: ["tabs.sleep", SleepPace.key], words: ["memory", "discard", "suspend", "ram"], kind: .wide),
        .init(id: "tabs.close.after", group: "memory", icon: "timer",
              title: "Close tabs left alone", detail: "",
              more: "Counted from when you last left the tab, while Aura is quit too. Pinned, named and grouped tabs stay; ⇧⌘T brings one back.",
              keys: ["tabs.close.after"], words: ["auto close", "archive", "clean up"]),
        .init(id: "swipe.close", group: "memory", icon: "arrow.left.square",
              title: "Close a tab by swiping back", detail: "",
              more: "Swiping back from a tab's first page is ⌘W. A pin keeps its page, and a small window closes as it always has.",
              keys: ["swipe.close"], words: ["gesture", "trackpad", "swipe", "back", "close tab", "dismiss"]),
        .init(id: "tabs.shortcuts", group: "tabbar", icon: "command",
              title: "Tab numbers while ⌘ is held", detail: "",
              keys: ["tabs.shortcuts"], words: ["numbers", "shortcut"]),
        .init(id: "tabs.address", group: "tabbar", icon: "lock",
              title: "Address on the current tab", detail: "",
              more: "The site in place of the title; the title returns under the pointer. Look-alike names show as they are, and plain http says Not secure.",
              keys: ["tabs.address"], words: ["url", "domain", "security", "address bar"]),

        // Browsing
        .init(id: "search.engine", group: "search", icon: "magnifyingglass",
              title: "Search engine", detail: "",
              keys: ["search.engine", "search.custom"], words: ["search with", "google", "duckduckgo", "engine", "kagi", "bing"]),
        .init(id: "search.suggest", group: "search", icon: "text.magnifyingglass",
              title: "Search suggestions", detail: "",
              more: "Suggestions show under the address field. Never from a private tab, and never an address.",
              keys: ["search.suggest"], words: ["autocomplete", "suggest"]),
        .init(id: "search.keywords", group: "search", icon: "character.cursor.ibeam",
              title: "Site shortcuts", detail: "",
              more: "A word before a search runs it on that site: \"yt cats\".",
              keys: ["search.keywords"], words: ["keyword", "bang"]),
        .init(id: "links.little", group: "links", icon: "rectangle.on.rectangle",
              title: "Other apps' links in a small window", detail: "",
              more: "To read and close, or keep with Open in Aura (⌘O).",
              keys: ["links.little"], words: ["little arc", "mini window"]),
        .init(id: "reader.twins", group: "reading", icon: "doc.text",
              title: "Read the site's own Markdown", detail: "",
              more: "Most docs sites publish one. Its text is escaped, so nothing in it can run.",
              keys: ["reader.twins"], words: ["markdown", "reader"]),
        .init(id: "reader.follows", group: "reading", icon: "circle.righthalf.filled",
              title: "Reading mode follows appearance", detail: "",
              more: "A switch in its corner sets an article light, dark or as the window is, kept for the next one.",
              keys: ["reader.follows"], words: ["reader", "dark"]),
        .init(id: "float.style", group: "video", icon: "pip",
              title: "Floating video window", detail: "Aura's window, or Picture in Picture",
              more: "Aura's window floats a video without a click and keeps its page alive in it. Picture in Picture is the one Safari uses, with the system's controls.",
              keys: ["float.style"], words: ["pip", "picture in picture", "mini player"]),
        .init(id: "float.own", group: "video", icon: "pip.exit",
              title: "Float video on leaving its tab", detail: "",
              more: "It goes back into its tab when you return. ⇧⌘P floats one by hand.",
              keys: ["float.leave", "float.away"], words: ["pip", "picture in picture", "switch apps"], kind: .wide),
        .init(id: "media.click", group: "video", icon: "play.slash",
              title: "Videos wait for a click", detail: "",
              more: "Even without sound.",
              keys: [Preferences.waitsKey], words: ["autoplay", "auto-play"]),
        .init(id: "fullscreen.escapeTwice", group: "video", icon: "escape",
              title: "Press Esc twice to leave full screen", detail: "",
              more: "The first press shows a reminder.",
              keys: ["fullscreen.escapeTwice"], words: ["escape", "full screen"]),
        .init(id: "pageZoom", group: "pages", icon: "plus.magnifyingglass",
              title: "Page zoom", detail: "Starting zoom for every site. ⌘+ and ⌘− are kept per site",
              keys: ["pageZoom"], words: ["zoom", "size", "scale"]),
        .init(id: "pages.120", group: "pages", icon: "speedometer",
              title: "Pages at 120 Hz", detail: "",
              more: "Animations and scrolling in pages at up to 120 frames a second, where Safari draws 60.",
              keys: ["pages.120.mode", "pages.120"], words: ["promotion", "frame rate", "fps", "smooth", "120"]),

        // Spaces & Pins
        .init(id: "arc.setup", group: "arc", icon: "wand.and.stars",
              title: "Set Up Like Arc", detail: "",
              more: "Tabs on the left, Spaces, pinned rows, pins that keep their site, and a floating new tab. Undo puts back what you had.",
              words: ["arc", "the browser company"]),
        .init(id: "arc.import", group: "arc", icon: "square.and.arrow.down",
              title: "Import Arc's spaces and pins", detail: "Spaces, pinned tabs and folders",
              words: ["arc", "import"]),
        .init(id: "spaces", group: "spaces", icon: "square.stack.3d.up",
              title: "Spaces", detail: "Separate sets of tabs, switched with ⌃1–⌃9 or a swipe",
              more: "Each space signs in where the others do or starts afresh. Mission Control's own ⌃1–⌃9, if you turned them on, take those keys first.",
              keys: ["spaces"], words: ["workspaces", "profiles"]),
        .init(id: "profiles", group: "spaces", icon: "person.2",
              title: "Profiles", detail: "Separate sign-ins, history and bookmarks",
              more: "Each in windows of its own. Extensions, passwords and settings are shared.",
              words: ["profile", "accounts", "work", "personal"]),
        .init(id: "pins.keep", group: "pins", icon: "pin.circle",
              title: "Pins keep their site", detail: "",
              more: "A pin closed with ⌘W, or left open when Aura quits, comes back at the page it was pinned at.",
              keys: ["pins.home"], words: ["pinned tabs", "go home", "reset pin"]),
        // Arc's second peek switch, with Arc's note under it (Links › Peek):
        // the plain click is the pin's alone, and a tab in the row is left to
        // navigate as it always did. A row of its own rather than half of
        // "Pins keep their site", which is where it could be neither found
        // nor turned off without taking ⌘W's way home with it (Drice, 27 Oct
        // 2026).
        .init(id: "pins.peek", group: "pins", icon: "eye",
              title: "Open links from a pin in a peek", detail: "Only a click on a link to another site",
              more: "The page opens in the panel over the pin, which stays where it was. Off, that click opens a tab beside the pin instead. Links within the site go in the pin as they always have.",
              keys: ["pins.peek"], words: ["peek", "preview", "pinned tabs", "click"]),
        .init(id: "pins.list", group: "pins", icon: "list.bullet.rectangle",
              title: "Pinned rows", detail: "",
              more: "Pins as rows under the squares, and a line with Clear over the rest. Right-click a tab to pin it as a row.",
              keys: ["pins.list"], words: ["arc", "pinned"], parent: "tabs.layout"),
        .init(id: "newtab.floating", group: "opening", icon: "rectangle.and.text.magnifyingglass",
              title: "New tab in a floating field", detail: "",
              more: "⌘T raises the address field over the page. Return opens what you typed; Escape, ⌘W or a click outside puts it away.",
              keys: ["newtab.floating"], words: ["command bar", "cmd t", "spotlight"]),
        .init(id: "commandbar", group: "opening", icon: "chevron.right.square",
              title: "Address bar commands", detail: "",
              more: "\"settings\" or \"new tab\" alone in the address field goes there.",
              keys: ["commandbar"], words: ["commands", "command palette"]),
        .init(id: "start.fresh", group: "opening", icon: "sunrise",
              title: "Start with a fresh window", detail: "",
              more: "Pins, groups and named tabs come back; last time's other tabs don't.",
              keys: [Preferences.freshKey], words: ["restore", "session", "startup"]),

        // Passwords
        .init(id: "passwords.open", group: "passwords", icon: "key.viewfinder",
              title: "Saved passwords", detail: "In the macOS keychain, shown with Touch ID", words: ["keychain"]),
        .init(id: "passwords.save", group: "passwords", icon: "square.and.arrow.down",
              title: "Offer to save passwords", detail: "",
              more: "Asked once per site, never again for a site you refuse.",
              keys: ["passwords.save"], words: ["save password"]),
        .init(id: "passwords.fill", group: "passwords", icon: "rectangle.and.pencil.and.ellipsis",
              title: "Fill in sign-ins", detail: "",
              keys: ["passwords.fill"], words: ["autofill", "login"]),
        .init(id: "passkeys", group: "passwords", icon: "person.badge.key",
              title: "Offer passkeys", detail: "",
              more: "Touch ID or an iCloud passkey, on sites that offer one.",
              keys: ["passkeys"], words: ["webauthn", "touch id"]),
        .init(id: "passwords.apple", group: "apple", icon: "applelogo",
              title: "Accounts from Apple Passwords", detail: "",
              more: "Under the sign-in box. Unofficial: Aura talks to the helper Apple made for its Chrome extension, as that extension. Never in private tabs.",
              keys: ["passwords.apple"], words: ["icloud keychain", "apple"]),

        // Privacy
        .init(id: "shield", group: "blocking", icon: "shield.lefthalf.filled",
              title: "Block ads and trackers", detail: "",
              more: "EasyList and EasyPrivacy, kept by other people: the requests not made, and the boxes they leave behind hidden.",
              keys: ["shield"], words: ["adblock", "ad blocker", "ads"]),
        .init(id: "shield.scriptlets", group: "blocking", icon: "shield.checkerboard",
              title: "Answer ad-block checks", detail: "",
              more: "A site asks whether a blocker is here by running a script and reading the answer. A small script from the list runs first, so the answer is the one the site wants. Off, a site that asks shows its wall instead of the page.",
              keys: ["shield.scriptlets"], words: ["anti-adblock", "detect", "scriptlets"]),
        .init(id: "sites.keep", group: "blocking", icon: "eye.slash",
              title: "Prevent cross-site tracking", detail: "",
              more: "Off, sites you rarely open keep their sign-ins, and trackers inside other sites can follow you across them again. Private tabs keep it on.",
              keys: ["sites.keep"], words: ["itp", "cookies", "tracking"]),
        .init(id: "notifications.ask", group: "permissions", icon: "bell.badge",
              title: "Let sites ask to send notifications", detail: "",
              more: "Only a site you allow reaches your Mac's notifications. Private tabs are never asked.",
              keys: ["notifications.ask"], words: ["notifications", "alerts", "push"]),
        .init(id: "privacy.forget", group: "permissions", icon: "arrow.uturn.backward.circle",
              title: "Camera, microphone, location and notifications", detail: "",
              more: "What each site was allowed or refused, and the sites whose videos don't float.",
              words: ["permissions", "camera", "microphone", "location", "reset"]),
        .init(id: "clear.history", group: "clear", icon: "clock.arrow.circlepath",
              title: "History", detail: "", words: ["clear history"]),
        .init(id: "clear.cookies", group: "clear", icon: "person.crop.circle.badge.xmark",
              title: "Cookies and sign-ins", detail: "Signs out of every site", words: ["cookies", "sign out"]),
        .init(id: "clear.cache", group: "clear", icon: "internaldrive",
              title: "Cache", detail: "Only what was fetched to draw pages", words: ["clear cache"]),

        // Keyboard & Mouse
        .init(id: "links.peek", group: "mouse", icon: "eye",
              title: "Peek at a link", detail: "",
              more: "The page opens in a panel over the one you're reading. Escape puts it away; the other button keeps it as a tab.",
              keys: ["links.peek", "links.peekClick"], words: ["preview", "shift click", "peek"]),
        .init(id: "autoscroll", group: "mouse", icon: "arrow.up.and.down.circle",
              title: "Scroll with the middle button", detail: "",
              more: "Click the wheel, then move the mouse to scroll.",
              keys: ["autoscroll"], words: ["middle click", "autoscroll", "wheel"]),
        .init(id: "swipe.history", group: "mouse", icon: "hand.draw",
              title: "Hold a swipe to pick from history", detail: "",
              more: "Swipe back or forward and keep your fingers down: the pages that way appear, and moving up or down picks one.",
              keys: ["swipe.history"], words: ["gesture", "trackpad", "back"]),

        // About
        .init(id: "updates.version", group: "updates", icon: "arrow.down.app",
              title: "Updates", detail: "Checked every hour on its own", words: ["version", "update"]),
        .init(id: "updates.auto", group: "updates", icon: "arrow.triangle.2.circlepath",
              title: "Install updates on its own", detail: "",
              more: "Off, Aura still looks every hour and tells you, and installs when you press Install.",
              keys: [Updater.installKey], words: ["automatic updates"]),
        .init(id: "about.feedback", group: "updates", icon: "envelope",
              title: "Feedback", detail: "",
              more: "Opens a draft with the version already in it.", words: ["bug", "feedback", "report"]),
        .init(id: "about.notes", group: "updates", icon: "sparkles",
              title: "Release notes", detail: "", words: ["release notes", "changelog"]),
        .init(id: "bench", group: "developer", icon: "terminal",
              title: "Let a script drive Aura", detail: "",
              more: "A local socket for testing. Its tabs open beside yours with a flask on them and never take over. See ./bench.",
              keys: ["bench"], words: ["automation", "script", "developer"]),

        // Moved to a menu, or always on: only the find field says so.
        .init(id: "autocorrect", group: "pages", icon: "textformat.abc.dottedunderline",
              title: "Correct spelling as you type", detail: "Now in Edit › Spelling and Grammar",
              keys: ["autocorrect"], words: ["autocorrect", "spelling", "spell"], findOnly: true),
        .init(id: "note.split", group: "window", icon: "rectangle.split.2x1",
              title: "Split View", detail: "Always available: drag a tab onto a page, or press ⌥⌘N",
              keys: ["splitView"], words: ["split", "side by side"], kind: .note, findOnly: true),
        .init(id: "note.groups", group: "newtabs", icon: "folder",
              title: "Tab groups", detail: "Always available: right-click a tab › Add to New Group",
              keys: ["tabs.groups"], words: ["groups", "folders"], kind: .note, findOnly: true),
        .init(id: "note.panel", group: "links", icon: "sidebar.right",
              title: "Websites in the side panel", detail: "Always available: View › Side Panel, or right-click a tab",
              keys: ["panel.sites"], words: ["side panel", "claude", "chatgpt"], kind: .note, findOnly: true),
        .init(id: "note.translate", group: "pages", icon: "translate",
              title: "Translate pages on this Mac", detail: "Always available: right-click a page › Translate Page",
              keys: ["translate.pages"], words: ["translate", "language"], kind: .note, findOnly: true),
        .init(id: "note.awake", group: "memory", icon: "sun.max",
              title: "Keep selected sites awake", detail: "Always available: Keep This Site Awake, on the site's card",
              keys: ["tabs.keepAwake"], words: ["awake", "sleep"], kind: .note, findOnly: true),
        .init(id: "note.sitesearch", group: "search", icon: "arrow.right.to.line.compact",
              title: "Search a site from the address field", detail: "Always available: type red, then Tab, and search Reddit",
              keys: ["search.sites"], words: ["tab to search", "site search"], kind: .note, findOnly: true),
        .init(id: "note.sharedpins", group: "pins", icon: "pin",
              title: "Pins in every space", detail: "Always available with Spaces: right-click a pin › Keep in Every Space",
              keys: ["pins.shared"], words: ["favorites", "shared pins"], kind: .note, findOnly: true),
        .init(id: "note.pinback", group: "pins", icon: "arrow.uturn.backward",
              title: "A pin's number again goes back", detail: "Always available: press a pin's ⌘ number again to go back",
              keys: ["pins.numberBack"], words: ["cmd 1", "toggle"], kind: .note, findOnly: true),
        .init(id: "note.switcher", group: "mouse", icon: "rectangle.stack",
              title: "Keys in the tab switcher", detail: "Always available: ⌃W, ⌃R, ⌃M and ⌃O while ⌃Tab is up",
              keys: ["switcher.keys"], words: ["ctrl tab", "switcher"], kind: .note, findOnly: true),
        .init(id: "note.links", group: "links", icon: "link",
              title: "Show where links go", detail: "Always available: a link's address at the bottom of the page",
              keys: ["links.show"], words: ["status bar", "hover"], kind: .note, findOnly: true),
        .init(id: "note.flick", group: "video", icon: "hand.raised.fingers.spread",
              title: "Flick the floating video to a corner", detail: "Always available: two fingers send it to the corner they point at",
              keys: ["float.flicks"], words: ["flick", "corner"], kind: .note, findOnly: true),
    ]

    static func item(_ id: String) -> SettingsItem? { items.first { $0.id == id } }

    // MARK: - finding

    /// The rows whose words match what was typed, in the order of the
    /// sections. Every word typed has to be found somewhere in the row.
    static func find(_ typed: String) -> [SettingsItem] {
        let words = typed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let order = SettingsPanel.Page.allCases
        return items
            .filter { item in
                let group = SettingsIndex.group(item.group)
                let hay = ([item.title, item.detail, item.more ?? "", group?.title ?? "", item.page.title]
                    + item.words + item.keys).joined(separator: " ").lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
            .sorted { (order.firstIndex(of: $0.page) ?? 0, groupOrder($0.group)) < (order.firstIndex(of: $1.page) ?? 0, groupOrder($1.group)) }
    }

    private static func groupOrder(_ id: String) -> Int { groups.firstIndex { $0.id == id } ?? 0 }

    /// Whether a dependent row means anything as things are set now. Its
    /// section hides it otherwise; the find field shows it dimmed.
    @MainActor static func applies(_ item: SettingsItem, _ prefs: Preferences) -> Bool {
        switch item.id {
        case "pages.dusk": return prefs.look != .light
        case "sidebar.hides", "layout.cards", "sidebar.roomy", "pins.list": return prefs.sidebar
        case "toolbar.left": return !prefs.sidebar
        default: return true
        }
    }

    /// What a dimmed dependent row says instead of its own line.
    static func needs(_ item: SettingsItem) -> String {
        switch item.id {
        case "pages.dusk": return "Requires Dark or Auto"
        case "toolbar.left": return "Requires the tabs across the top"
        default: return "Requires the tabs down a side"
        }
    }
}

// MARK: - merged controls

/// Tabs: across the top, or a column down either side. Reads and writes
/// `sidebar` and `sidebar.position`, as the two switches did.
enum TabsLayout: String, CaseIterable, Identifiable {
    case top, left, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// Sleep tabs: Never, or how soon. `tabs.sleep` and `tabs.sleep.pace`.
enum SleepChoice: String, CaseIterable, Identifiable {
    case never, later, normal, sooner
    var id: String { rawValue }
    var title: String { self == .never ? "Never" : pace!.title }
    var pace: SleepPace? { SleepPace(rawValue: rawValue) }
    var detail: String {
        guard let pace else { return "No tab ever sleeps." }
        return Localized("Away \(pace.detail), a tab sleeps and wakes when you go back to it.")
    }
}

/// Float the video on its own: `float.leave` and `float.away`.
enum FloatOwn: String, CaseIterable, Identifiable {
    case never, tabs, tabsOrApps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: return "Never"
        case .tabs: return "Switching tabs"
        case .tabsOrApps: return "Tabs or apps"
        }
    }
}

/// Peek at a link: Off, or the click that does it. `links.peek` and
/// `links.peekClick`.
enum PeekChoice: String, CaseIterable, Identifiable {
    case off, shift, optionShift, optionCommand
    var id: String { rawValue }
    var title: String { self == .off ? "Off" : click!.title }
    var click: PeekClick? { PeekClick(rawValue: rawValue) }
}

extension Preferences {
    var tabsLayout: TabsLayout {
        get { !sidebar ? .top : (sidePosition == .right ? .right : .left) }
        set {
            if newValue == .top {
                sidebar = false
            } else {
                sidePosition = newValue == .right ? .right : .left
                sidebar = true
            }
        }
    }

    var sleepChoice: SleepChoice {
        get { sleepsTabs ? (SleepChoice(rawValue: sleepPace.rawValue) ?? .normal) : .never }
        set {
            if let pace = newValue.pace { sleepPace = pace; sleepsTabs = true } else { sleepsTabs = false }
        }
    }

    /// Away alone (never seen from the switches, but possible) reads as the
    /// nearest choice that includes it.
    var floatOwn: FloatOwn {
        get { floatsAway ? .tabsOrApps : (floatsOnLeave ? .tabs : .never) }
        set {
            floatsOnLeave = newValue != .never
            floatsAway = newValue == .tabsOrApps
        }
    }

    /// Both halves of a pin that keeps its site at once: ⌘W's way home
    /// (`pins.home`) and the peek a plain click out to another site opens
    /// (`pins.peek`). Settings shows them as two rows and this is neither of
    /// them; it is what Set Up Like Arc turns on, what undo puts back, and
    /// what the bench reads as "pins.keep".
    var pinsKeepSite: Bool {
        get { pinsGoHome || pinsPeek }
        set { pinsGoHome = newValue; pinsPeek = newValue }
    }

    var peekChoice: PeekChoice {
        get { peeksLinks ? (PeekChoice(rawValue: peekClick.rawValue) ?? .shift) : .off }
        set {
            if let click = newValue.click { peekClick = click; peeksLinks = true } else { peeksLinks = false }
        }
    }

    /// Set Up Like Arc: what it turns on, and what was there before, so
    /// Undo can put it back.
    struct ArcSetup {
        var layout: TabsLayout
        var spaces: Bool
        var rows: Bool
        var keep: (home: Bool, peek: Bool)
        var floating: Bool
    }

    var arcSnapshot: ArcSetup {
        ArcSetup(layout: tabsLayout, spaces: usesSpaces, rows: listsPins, keep: (pinsGoHome, pinsPeek), floating: floatingNewTab)
    }

    var looksLikeArc: Bool {
        tabsLayout == .left && usesSpaces && listsPins && pinsGoHome && pinsPeek && floatingNewTab
    }

    /// Turns Arc's way on and says what changed.
    @discardableResult
    func setUpLikeArc() -> [String] {
        var changed: [String] = []
        if tabsLayout != .left { tabsLayout = .left; changed.append("tabs on the left") }
        if !usesSpaces { usesSpaces = true; changed.append("Spaces") }
        if !listsPins { listsPins = true; changed.append("pinned rows") }
        if !(pinsGoHome && pinsPeek) { pinsKeepSite = true; changed.append("pins keep their site") }
        if !floatingNewTab { floatingNewTab = true; changed.append("the floating new tab") }
        return changed
    }

    func restore(_ before: ArcSetup) {
        tabsLayout = before.layout
        usesSpaces = before.spaces
        listsPins = before.rows
        pinsGoHome = before.keep.home
        pinsPeek = before.keep.peek
        floatingNewTab = before.floating
    }
}

// MARK: - for the bench

extension SettingsIndex {
    /// The merged controls as Settings shows them, and the switches whose
    /// defaults changed: what Tests/settings_layout.py reads back.
    @MainActor static func values(_ prefs: Preferences) -> [String: Any] {
        [
            "tabs.layout": prefs.tabsLayout.rawValue,
            "tabs.sleep": prefs.sleepChoice.rawValue,
            "float.own": prefs.floatOwn.rawValue,
            "pins.keep": prefs.pinsKeepSite,
            "pins.home": prefs.pinsGoHome,
            "pins.peek": prefs.pinsPeek,
            "links.peek": prefs.peekChoice.rawValue,
            "pages.120": prefs.fastPages.rawValue,
            "swipe.history": prefs.holdsHistory,
            "swipe.close": prefs.swipeClosesTab,
            "tabs.address": prefs.showsAddress,
            "links.show": prefs.showsLinks,
            "float.flicks": prefs.floatFlicks,
            "arc": prefs.looksLikeArc,
            "always": [
                "splitView": prefs.splitView, "tabs.groups": prefs.usesTabGroups,
                "panel.sites": prefs.sitesInPanel, "translate": PageTranslator.enabled,
                "tabs.keepAwake": prefs.keepsSitesAwake, "search.sites": prefs.searchesSites,
                "pins.shared": prefs.sharesPins, "pins.numberBack": prefs.pinNumberGoesBack,
                "switcher.keys": prefs.switcherKeys,
            ],
        ]
    }

    /// A merged control moved as Settings moves it. False for an id or a
    /// value it doesn't know.
    @MainActor static func apply(_ id: String, _ value: Any, to prefs: Preferences) -> Bool {
        switch id {
        case "tabs.layout":
            guard let layout = (value as? String).flatMap(TabsLayout.init) else { return false }
            prefs.tabsLayout = layout
        case "tabs.sleep":
            guard let choice = (value as? String).flatMap(SleepChoice.init) else { return false }
            prefs.sleepChoice = choice
        case "float.own":
            guard let choice = (value as? String).flatMap(FloatOwn.init) else { return false }
            prefs.floatOwn = choice
        case "pins.keep":
            guard let on = value as? Bool else { return false }
            prefs.pinsKeepSite = on
        case "links.peek":
            guard let choice = (value as? String).flatMap(PeekChoice.init) else { return false }
            prefs.peekChoice = choice
        case "arc.setup":
            prefs.setUpLikeArc()
        default:
            return false
        }
        return true
    }

    static func describe(_ item: SettingsItem) -> [String: Any] {
        ["id": item.id, "page": item.page.rawValue, "group": item.group,
         "groupTitle": group(item.group)?.title ?? "", "title": item.title, "detail": item.detail,
         "keys": item.keys, "findOnly": item.findOnly, "note": item.kind == .note,
         "parent": item.parent ?? ""]
    }
}
