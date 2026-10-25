import AppKit
import WebKit

// Right-click on a block, with "Hide This Element" in the menu.
//
// WebKit's own page menu has no public hook — the same reason ImageMenu.swift
// stands in for the image one — so the page's own menu is asked to step aside
// for exactly the element a right-click landed on: the page's `contextmenu`
// event is answered here, the element under the pointer is named, and this
// app's menu is popped where the pointer already is.
//
// What is deliberately left alone, because WebKit's menu is better at it and
// taking it away would be a loss: a link, a picture, a text field, anything
// being typed into, and any page with text selected. What is left — the div
// that holds an advert, the promo card, the shell a blocked advert leaves
// behind — is exactly the thing somebody wants to point at and be rid of.

final class ElementRelay: NSObject, WKScriptMessageHandler {
    static let name = "officeElement"

    weak var tab: Tab?

    /// The main frame only: a selector is kept by host and put back as a
    /// stylesheet on every frame, so naming one from inside somebody else's
    /// frame is naming something this side cannot promise.
    static let watch = """
    (function () {
      if (window.__officeElements) return;
      window.__officeElements = true;
      document.addEventListener('contextmenu', function (e) {
        // A right-click of yours only: a page can dispatch one itself, and
        // would open this menu whenever it liked — under your next click.
        if (!e.isTrusted) return;
        var el = e.target;
        if (!el || el.nodeType !== 1) return;
        // The things WebKit's own menu does better, and the one thing a
        // right-click is for when it is not about hiding anything.
        if (el.closest('a[href], img, input, textarea, select, video, audio, [contenteditable]')) return;
        var picked = window.getSelection && String(window.getSelection());
        if (picked && picked.length) return;
        var veil = window.__officeVeil;
        var relay = window.webkit && webkit.messageHandlers && webkit.messageHandlers.officeElement;
        if (!veil || !veil.describe || !relay) return;
        var about = veil.describe(el);
        if (!about || !about.selector) return;
        e.preventDefault();
        relay.postMessage(about);
      }, true);
    })();
    """

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let selector = body["selector"] as? String,
              !selector.isEmpty,
              let tab
        else { return }
        // The page names this selector and the app keeps it, so only what the
        // page's own naming produced is let through: a selector short enough
        // to be a path, and no script in it.
        guard selector.count < 500, !selector.lowercased().contains("javascript:") else { return }
        tab.blockMenu(selector: selector,
                      label: body["label"] as? String ?? selector,
                      note: body["note"] as? String ?? "")
    }
}

/// A menu item that runs a closure — NSMenuItem wants a target and a selector,
/// and this is the one-line way to give it both. Shared with ImageMenu.swift,
/// which needed the same thing first.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title.localized, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not from a nib") }

    @objc private func fire() { run() }
}

extension Browser {
    /// The menu a right-click on a block puts up: the one thing WebKit's own
    /// menu cannot be given, beside the two things taking its place would
    /// otherwise cost. Hiding is the same handing-over a click in pointing
    /// mode makes, so a block hidden from here is hidden the same way, for
    /// the same site, and back the same way.
    func showBlockMenu(for tab: Tab, selector: String, label: String, note: String) {
        guard let page = tab.built, let window = page.view.window else { return }
        let view = page.view
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem("Hide This Element") {
            tab.picked(selector: selector, label: label, note: note)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Reload") { [weak self, weak tab] in
            guard let self, let tab, tab === self.active else { return }
            self.reload()
        })
        menu.addItem(ClosureMenuItem("Inspect Element") { [weak self, weak tab] in
            guard let self, let tab, tab === self.active else { return }
            self.toggleInspector()
        })

        let atWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        menu.popUp(positioning: nil, at: view.convert(atWindow, from: nil), in: view)
    }
}
