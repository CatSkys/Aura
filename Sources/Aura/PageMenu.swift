import AppKit

// The menu a right-click on the page's own ground puts up.
//
// WebKit draws its own page menu, and a good one, for what it knows how to
// handle: a link, a picture, a field, a page with words selected — ElementMenu
// steps aside for exactly those. On a block of the page that is none of them
// the menu is this app's, and it has the page's doors at the top as Safari's
// and Arc's do, then what keeps, prints and shares the page, then what can be
// done to the block itself.
//
// Everything here is a door Aura already has, reached from the menu instead of
// from the menu bar: the same Save Page As (⌘S), Export as PDF, Print (⌘P),
// Share and Translate, and the Web Inspector.

extension Browser {
    func showPageMenu(for tab: Tab, selector: String, label: String, note: String) {
        guard let page = tab.built, let window = page.view.window else { return }
        let view = page.view
        let menu = NSMenu()
        // Every row says for itself whether it may be pressed: without this,
        // AppKit asks the responder chain, which knows none of them.
        menu.autoenablesItems = false

        func add(_ title: String, on: Bool = true, _ run: @escaping () -> Void) {
            let item = ClosureMenuItem(title, run)
            item.isEnabled = on
            menu.addItem(item)
        }

        add("Back", on: tab.canGoBack) { tab.back() }
        add("Forward", on: tab.canGoForward) { tab.forward() }
        add(tab.loading ? "Stop" : "Reload", on: tab.isWeb) {
            if tab.loading { tab.stop() } else { tab.reload() }
        }
        // Keeping, printing and sharing are the page on screen's: the side
        // panel has a page of its own, and a right-click in it is not the
        // page these would act on.
        let showing = tab === active
        menu.addItem(.separator())
        add("Save Page As…", on: showing && tab.isWeb) { [weak self] in self?.savePage() }
        add("Export as PDF…", on: showing && tab.isWeb) { [weak self] in self?.exportPDF() }
        add("Print…", on: showing && tab.isWeb) { [weak self] in self?.printPage() }
        add("Share…", on: showing) { [weak self] in self?.share() }
        // Translate Page, off unless switched on in Settings (Translate.swift).
        if PageTranslator.enabled {
            let translated = tab.translator != nil && tab.translation?.failed != true
            let language = PageTranslator.name(PageTranslator.code(PageTranslator.reader))
            add(translated ? Localized("Show Original") : Localized("Translate Page to \(language)")) {
                tab.toggleTranslation()
            }
        }
        menu.addItem(.separator())
        add("Hide This Element") { tab.picked(selector: selector, label: label, note: note) }
        menu.addItem(.separator())
        add("Inspect Element", on: tab === active) { [weak self] in self?.toggleInspector() }

        let atWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        menu.popUp(positioning: nil, at: view.convert(atWindow, from: nil), in: view)
    }
}
