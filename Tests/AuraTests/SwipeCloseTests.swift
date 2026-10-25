import AppKit
import XCTest
@testable import Aura

/// The gate on the swipe that closes a tab, kept where it is cheap to check:
/// the gesture itself needs two fingers, and `Tests/swipe_close.py` drives
/// those through the bench.
@MainActor
final class SwipeCloseTests: XCTestCase {
    override class func setUp() {
        setenv("AURA_PROBE", "swipe-close-\(getpid())", 1)
        super.setUp()
    }

    override func tearDown() {
        Swipe.closesTab = false
        super.tearDown()
    }

    private func makeBrowser() -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.newTab()
        browser.tabs.last?.restore(url: URL(string: "https://one.example/")!, title: "one")
        return browser
    }

    func testOffByDefaultAndNothingCloses() {
        let browser = makeBrowser()
        let tab = browser.tabs.last!
        XCTAssertFalse(Swipe.closesTab)
        XCTAssertFalse(tab.closesOnSwipeBack)
    }

    func testOnClosesATabAndPinsKeepTheirPage() {
        let browser = makeBrowser()
        let tab = browser.tabs.last!
        Swipe.closesTab = true
        XCTAssertTrue(tab.closesOnSwipeBack)

        browser.pin(tab)
        XCTAssertFalse(tab.closesOnSwipeBack, "a pin's first page is the page it was pinned at")
    }

    func testABlankTabIsLeftAlone() {
        let browser = makeBrowser()
        browser.newTab()
        let blank = browser.tabs.last!
        XCTAssertTrue(blank.isBlank)
        Swipe.closesTab = true
        XCTAssertFalse(blank.closesOnSwipeBack, "a blank tab has nothing behind it to leave")
    }

    func testATabNoWindowHasTakenHasNoSwipeClose() {
        Swipe.closesTab = true
        let loose = Tab(configuration: Web.configuration())
        XCTAssertFalse(loose.closesOnSwipeBack)
    }
}
