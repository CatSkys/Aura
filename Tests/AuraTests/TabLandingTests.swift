import AppKit
import XCTest
@testable import Aura

/// Where ⌘W leaves you: on the page a link was clicked on when one opened the
/// tab, and otherwise on a tab that is already open rather than on the
/// neighbour whichever way it is — a sleeping tab landed on is a page fetched
/// that nobody asked for.
///
/// No Browser is made here on purpose. One made in a suite leaves its tabs in
/// the session the next suite restores, and TabSelection — which runs right
/// after this one — counts them; four `Tab`s are pages enough to ask, since
/// the two lines `close` stands on are `Browser.landing(after:at:in:)` and
/// `Browser.awake(nearest:in:)`.
@MainActor
final class TabLandingTests: XCTestCase {
    override class func setUp() {
        setenv("AURA_PROBE", "tab-landing-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    /// The neighbour on the right, when it is holding its page.
    func testTheTabOnTheRightComesFirst() {
        let row = [sleeping("one"), open()]
        XCTAssertEqual(Browser.awake(nearest: 0, in: row)?.id, row[1].id)
    }

    /// Both beside it, both open: the right one, as the neighbour always was.
    func testTheTabOnTheRightWinsATie() {
        let row = [open(), open()]
        XCTAssertEqual(Browser.awake(nearest: 1, in: row)?.id, row[1].id)
    }

    /// The right neighbour asleep and the left one open: the left one, rather
    /// than waking what is next door.
    func testAnOpenTabFurtherAlongBeatsASleepingNeighbour() {
        let row = [open(), sleeping("two"), sleeping("three")]
        XCTAssertEqual(Browser.awake(nearest: 3, in: row)?.id, row[0].id)
    }

    /// Nothing open anywhere: ⌘W has its neighbour to wake, as before.
    func testNothingOpenAnywhereIsNothingToLandOn() {
        let row = [sleeping("one"), sleeping("two")]
        XCTAssertNil(Browser.awake(nearest: 0, in: row))
        XCTAssertNil(Browser.awake(nearest: 1, in: row))
    }

    /// A tab a link opened goes back to the page the link was clicked on, even
    /// with a nearer tab beside it.
    func testATabALinkOpenedGoesBackToItsPage() {
        let home = open()
        let link = open()
        link.opener = home.id
        let elsewhere = open()
        XCTAssertEqual(Browser.landing(after: link, at: 2, in: [home, elsewhere, link])?.id, home.id)
    }

    /// Another tab that page opened comes before the page itself: links off
    /// one page are read one after another, and the last of them hands you
    /// back.
    func testAnotherTabOfTheSameOpenComesFirst() {
        let home = open()
        let first = open()
        let second = open()
        first.opener = home.id
        second.opener = home.id
        XCTAssertEqual(Browser.landing(after: second, at: 2, in: [home, first, second])?.id, first.id)
    }

    /// A tab the closed one opened comes before all of them: the page it went
    /// on to.
    func testATabItOpenedComesFirst() {
        let home = open()
        let link = open()
        let on = open()
        link.opener = home.id
        on.opener = link.id
        XCTAssertEqual(Browser.landing(after: link, at: 1, in: [home, link, on])?.id, on.id)
    }

    /// The page that opened it asleep: nothing to land on, so ⌘W takes the
    /// neighbour rather than waking it.
    func testASleepingPageIsNothingToGoBackTo() {
        let home = sleeping("home")
        let link = open()
        link.opener = home.id
        XCTAssertNil(Browser.landing(after: link, at: 1, in: [home, link]))
    }

    /// Nothing opened it: the neighbour, as before.
    func testATabOpenedByHandHasNowhereToGoBackTo() {
        XCTAssertNil(Browser.landing(after: open(), at: 0, in: [open(), open()]))
    }

    /// A tab brought back from last time, holding its address and no page.
    private func sleeping(_ word: String) -> Tab {
        let tab = Tab(configuration: Web.configuration())
        tab.restore(url: URL(string: "https://\(word).example/")!, title: word)
        return tab
    }

    /// A tab with its page, which is what a blank one costs nothing to be.
    private func open() -> Tab {
        let tab = Tab(configuration: Web.configuration())
        XCTAssertTrue(tab.isBlank)
        return tab
    }
}
