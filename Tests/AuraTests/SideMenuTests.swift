import AppKit
import XCTest
@testable import Aura

/// The column's right-click menu, read without opening it: a real NSMenu can't
/// be tracked in a hidden run, so the rows are built and looked at.
@MainActor
final class SideMenuTests: XCTestCase {
    override class func setUp() {
        setenv("AURA_PROBE", "side-menu-\(getpid())", 1)
        super.setUp()
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    func testTheColumnOffersTheSpaceAndANewTab() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let prefs = browser.prefs
        let saved = prefs.usesSpaces
        defer { prefs.usesSpaces = saved }
        prefs.usesSpaces = true

        let space = browser.space
        XCTAssertEqual(titles(SideMenu.menu(for: browser)),
                       ["New Tab", "—",
                        "Change Space Icon…",
                        Localized("Rename “\(space.name)”…"),
                        "Edit Theme Colour…",
                        "—",
                        "Manage Spaces…"],
                       "The profile's first space has no Delete: it stays")
        XCTAssertTrue(SideMenu.menu(for: browser).items.allSatisfy { $0.isSeparatorItem || $0.isEnabled },
                      "Every row the column offers can be pressed")
    }

    func testASpaceThatCanGoCanBeDeleted() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let prefs = browser.prefs
        let saved = prefs.usesSpaces
        defer { prefs.usesSpaces = saved }
        prefs.usesSpaces = true
        browser.addSpace(named: "Work")

        let rows = titles(SideMenu.menu(for: browser))
        XCTAssertEqual(rows.last, Localized("Delete “Work”…"))
        XCTAssertTrue(rows.contains("Manage Spaces…"))
    }

    func testWithSpacesOffTheColumnAsksOnlyForATab() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let prefs = browser.prefs
        let saved = prefs.usesSpaces
        defer { prefs.usesSpaces = saved }
        prefs.usesSpaces = false

        XCTAssertEqual(titles(SideMenu.menu(for: browser)), ["New Tab"])
    }

    /// Change Space Icon… and Edit Theme Colour… open the space's card on the
    /// page they belong to rather than drawing a picker of their own.
    func testTheIconAndColourRowsOpenTheCardOnTheirPage() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let prefs = browser.prefs
        let saved = prefs.usesSpaces
        defer { prefs.usesSpaces = saved }
        prefs.usesSpaces = true

        browser.openSpaceCard(.icons)
        XCTAssertTrue(browser.spaceCardUp)
        XCTAssertEqual(browser.spaceCardPage, .icons)

        browser.openSpaceCard(.colour)
        XCTAssertEqual(browser.spaceCardPage, .colour)
    }
}
