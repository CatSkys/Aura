import AppKit
import WebKit
import XCTest
@testable import Aura

/// What WebKit's `willOpenMenu` hook does with a menu Aura built itself.
///
/// The hook is AppKit's — every menu shown from the view comes past it — and
/// it exists to put the page's rows into WebKit's menu. Run on Aura's own menu
/// it put them in twice: the page's right-click menu came up with Translate
/// Page at both ends.
@MainActor
final class PageMenuTests: XCTestCase {
    override class func setUp() {
        setenv("AURA_PROBE", "page-menu-\(getpid())", 1)
        super.setUp()
    }

    private func view(_ rows: Int, ofOurOwn: Bool) -> (PageView, NSMenu) {
        _ = NSApplication.shared
        let web = PageView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: WKWebViewConfiguration())
        // Whether the page is translated is asked of the view when the menu
        // opens; a page that is not, gives nothing to add.
        web.translating = { false }
        let menu = NSMenu()
        if ofOurOwn { menu.identifier = NSMenu.auraContextMenu }
        for row in 0..<rows { menu.addItem(withTitle: "Row \(row)", action: nil, keyEquivalent: "") }
        return (web, menu)
    }

    private func opened(_ web: PageView, _ menu: NSMenu) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        web.willOpenMenu(menu, with: event)
    }

    func testAMenuOfOurOwnIsLeftAsItWasBuilt() throws {
        let (web, menu) = view(5, ofOurOwn: true)
        try opened(web, menu)
        XCTAssertEqual(menu.items.map(\.title), ["Row 0", "Row 1", "Row 2", "Row 3", "Row 4"],
                       "Aura's own menu already has the page's rows; the hook would make a second of each")
    }

    func testWebKitsMenuStillGetsItsRows() throws {
        // WebKit's own menu is the one the hook is for, and it is recognised by
        // having no identifier of Aura's on it.
        let (web, menu) = view(1, ofOurOwn: false)
        try opened(web, menu)
        let added = menu.items.count - 1
        XCTAssertEqual(added, PageTranslator.enabled ? 2 : 0, "Translate Page, with a rule over it")
    }
}
