import AppKit
import XCTest
@testable import Aura

/// Where ⌘W leaves you: on a tab that is already open, rather than on the
/// neighbour whichever way it is — a sleeping tab landed on is a page fetched
/// that nobody asked for.
///
/// No Browser is made here on purpose. One made in a suite leaves its tabs in
/// the session the next suite restores, and TabSelection — which runs right
/// after this one — counts them; four `Tab`s are pages enough to ask, since
/// the one line `close` stands on is `Browser.awake(nearest:in:)`.
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
