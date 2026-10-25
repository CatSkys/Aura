import AppKit
import XCTest
@testable import Aura

/// The gate on the swipe that closes a tab, kept where it is cheap to check:
/// the gesture itself needs two fingers, and `Tests/swipe_close.py` drives
/// those through the bench.
///
/// No Browser is made here on purpose. One made in this suite leaves its tabs
/// in the session the next suite restores, and TabCapture and TabSelection —
/// which run right after this one — count them; the tabs below are pages
/// enough to ask, and Browser.prepare is the one line they stand in for.
@MainActor
final class SwipeCloseTests: XCTestCase {
    override class func setUp() {
        setenv("AURA_PROBE", "swipe-close-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    override func tearDown() {
        Swipe.closesTab = false
        super.tearDown()
    }

    /// A tab as Browser.prepare leaves one: a page, and ⌘W at the end of a
    /// swipe back.
    private func tab(_ address: String?) -> Tab {
        let tab = Tab(configuration: Web.configuration())
        tab.onSwipeClose = {}
        if let address { tab.restore(url: URL(string: address)!, title: "one") }
        return tab
    }

    func testOffUnlessAskedFor() {
        XCTAssertFalse(Swipe.closesTab)
        XCTAssertFalse(tab("https://one.example/").closesOnSwipeBack)
    }

    func testOnClosesTheTabItsPageIsIn() {
        Swipe.closesTab = true
        XCTAssertTrue(tab("https://one.example/").closesOnSwipeBack)
    }

    func testAPinKeepsItsPage() {
        Swipe.closesTab = true
        let pin = tab("https://one.example/")
        pin.pin = "O"
        XCTAssertFalse(pin.closesOnSwipeBack, "a pin's first page is the page it was pinned at")
    }

    func testABlankTabIsLeftAlone() {
        Swipe.closesTab = true
        let blank = tab(nil)
        XCTAssertTrue(blank.isBlank)
        XCTAssertFalse(blank.closesOnSwipeBack, "a blank tab has nothing behind it to leave")
    }

    func testATabNoWindowHasTakenHasNoSwipeClose() {
        Swipe.closesTab = true
        let loose = Tab(configuration: Web.configuration())
        XCTAssertFalse(loose.closesOnSwipeBack)
    }
}
