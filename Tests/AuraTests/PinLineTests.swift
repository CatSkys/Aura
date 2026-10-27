import XCTest
@testable import Aura

/// The line over the tabs in the column (SideBar.showsLine): with the pinned
/// rows on, it stands between what is kept — pins, rows, groups — and the
/// tabs Clear would close. A space of loose tabs alone used to wear it too,
/// which put a rule over the top of the tabs with nothing above them (idea
/// 444, and the screenshot that came with the report).
@MainActor
final class PinLineTests: XCTestCase {
    private func line(pins: Int = 0, listed: Int = 0, loose: Int = 0, groups: Int = 0, rows: Bool = true) -> Bool {
        SideBar.showsLine(pins: pins, listed: listed, loose: loose, groups: groups, rows: rows)
    }

    /// The report: pinned rows on, no pins, one tab. No line.
    func testLooseTabsAloneHaveNoLine() {
        XCTAssertFalse(line(loose: 1))
        XCTAssertFalse(line(loose: 12))
    }

    /// It comes with the first pin: a row above the tabs to keep apart.
    func testTheFirstRowBringsTheLine() {
        XCTAssertTrue(line(listed: 1, loose: 1))
        XCTAssertTrue(line(listed: 2, loose: 1))
    }

    /// A square pin is a pin: the line stands under it.
    func testASquarePinBringsTheLineToo() {
        XCTAssertTrue(line(pins: 1, loose: 3))
    }

    /// Or a group, which Clear keeps as it keeps the pins.
    func testAGroupBringsTheLine() {
        XCTAssertTrue(line(loose: 2, groups: 1))
    }

    /// Rows with nothing below them keep theirs: the line is where Clear
    /// hangs, and a row alone still says what it is.
    func testRowsWithNothingBelowThemStillDrawIt() {
        XCTAssertTrue(line(listed: 1))
    }

    /// With the pinned rows off there is no line at all — the squares are a
    /// block of their own and separated by their own gap.
    func testNoLineWithTheRowsOff() {
        XCTAssertFalse(line(pins: 4, listed: 2, loose: 5, groups: 3, rows: false))
    }

    /// Nothing at all: nothing on either side of a line there would be two
    /// of.
    func testNothingOnEitherSideIsNoLine() {
        XCTAssertFalse(line())
        XCTAssertFalse(line(pins: 3))
    }
}
