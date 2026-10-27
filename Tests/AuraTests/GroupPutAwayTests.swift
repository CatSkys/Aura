import AppKit
import XCTest
@testable import Aura

/// ⌘W on a tab in a group (Browser.close(_:puttingAway:)): Arc keeps a
/// folder's tabs, so the page is let go and the row stays where it was, to be
/// opened again where it left off. Everything else that closes — the cross,
/// the menu, Close Other Tabs and Close Tabs Below — closes for good, and a
/// row already put away has nothing left to put away.
@MainActor
final class GroupPutAwayTests: XCTestCase {
    private static var world: String?

    override class func setUp() {
        super.setUp()
        let name = "group-put-away-\(UUID().uuidString.lowercased().prefix(8))"
        world = name
        setenv("AURA_PROBE", name, 1)
    }

    override class func tearDown() {
        Disk.drain()
        if let world, Store.world == world {
            try? FileManager.default.removeItem(at: Store.folder)
            UserDefaults(suiteName: "com.officecommun.search.test.\(world)")?.removePersistentDomain(forName: "com.officecommun.search.test.\(world)")
        }
        unsetenv("AURA_PROBE")
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    /// A window of two pages, the first in a group of its own, on screen.
    private func window() -> (Browser, Tab, Tab) {
        let browser = Browser(record: WindowRecord())
        browser.prefs.usesTabGroups = true
        browser.tabs.first?.restore(url: URL(string: "https://one.example/")!, title: "one")
        browser.newTab()
        browser.tabs.last?.restore(url: URL(string: "https://two.example/")!, title: "two")
        let first = browser.tabs[0], second = browser.tabs[1]
        let group = browser.addTabGroup(containing: first)
        XCTAssertEqual(browser.group(of: first), group)
        browser.select(first)
        return (browser, first, second)
    }

    func testCommandWOnAGroupedTabLetsThePageGoAndKeepsTheRow() {
        let (browser, tab, other) = window()
        browser.closeFront()
        // Still in the row, still in its group — and holding no page.
        XCTAssertTrue(browser.tabs.contains { $0.id == tab.id })
        XCTAssertEqual(browser.group(of: tab), tab.groupID)
        XCTAssertTrue(tab.asleep)
        XCTAssertEqual(tab.address?.absoluteString, "https://one.example/")
        // Somewhere else came to the front; the page it went on to is not
        // fetched back for it.
        XCTAssertNotEqual(browser.activeID, tab.id)
        XCTAssertEqual(other.address?.absoluteString, "https://two.example/")
    }

    /// Pressed again on a row that is still put away — one brought back with
    /// the window at launch, before anything looked at it — ⌘W closes it for
    /// good rather than putting away what is already away.
    func testCommandWOnAPutAwayRowClosesItForGood() {
        let (browser, tab, _) = window()
        browser.closeFront()
        XCTAssertTrue(tab.asleep)
        browser.close(tab, puttingAway: true)
        XCTAssertFalse(browser.tabs.contains { $0.id == tab.id })
        XCTAssertTrue(browser.ghosts.contains { $0.url.absoluteString == "https://one.example/" })
    }

    /// The menu's Close Tab, and the cross, are not ⌘W: they close for good
    /// the first time.
    func testTheCrossClosesItForGood() {
        let (browser, tab, _) = window()
        browser.close(tab)
        XCTAssertFalse(browser.tabs.contains { $0.id == tab.id })
        XCTAssertTrue(browser.ghosts.contains { $0.url.absoluteString == "https://one.example/" })
    }

    /// A tab in no group is closed by ⌘W as it always was.
    func testAnUngroupedTabIsStillClosed() {
        let (browser, _, other) = window()
        browser.select(other)
        browser.closeFront()
        XCTAssertFalse(browser.tabs.contains { $0.id == other.id })
    }
}
