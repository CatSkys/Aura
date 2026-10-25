import XCTest
@testable import Aura

/// What the column's band holds at a given width (SideBand.swift): the fold
/// and the three doors while there is room, and a "…" for whatever gave way.
final class SideBandTests: XCTestCase {
    /// A window not in full screen has the lights' corner beside the band,
    /// as much of it as the column can afford at this width (SideBand.lights).
    private let lights = Metrics.sideLights

    private func corner(_ column: CGFloat) -> CGFloat {
        SideBand.lights(column: column, wanted: lights)
    }

    private func plan(_ column: CGFloat, lights: CGFloat? = nil) -> SideBand.Plan {
        SideBand.plan(column: column, lights: lights ?? self.lights)
    }

    /// The narrowest column that still holds the fold and the three doors
    /// with their roomy gaps: worked out from the band's own numbers, so a
    /// change to the lights' corner or a door's width moves the test with it.
    private var wholeRow: CGFloat {
        2 * SideBand.pad + lights
            + CGFloat(HelmDoor.allCases.count + 1) * SideBand.door
            + CGFloat(HelmDoor.allCases.count) * SideBand.wide
    }

    func testTheWholeRowWhileItFits() {
        let wide = plan(Metrics.side)
        XCTAssertTrue(wide.fold)
        XCTAssertEqual(wide.doors, HelmDoor.allCases)
        XCTAssertFalse(wide.more)
        XCTAssertEqual(wide.gap, SideBand.wide)
    }

    func testTheFoldAndTheAirAreWhatGiveWayFirst() {
        // The room the four doors and their gaps take, exactly.
        let exactly = plan(wholeRow)
        XCTAssertTrue(exactly.fold)
        XCTAssertFalse(exactly.more)

        // A point narrower, the row closes up and the fold goes into the "…":
        // the arrows, the ones reached for most, stay.
        let tight = plan(wholeRow - 1)
        XCTAssertFalse(tight.fold)
        XCTAssertEqual(tight.doors, [.back, .forward, .reload])
        XCTAssertTrue(tight.more)
        XCTAssertEqual(tight.gap, SideBand.tight)
    }

    func testTheArrowsStayAtTheColumnsNarrowest() {
        // 176 across, the narrowest the column goes: the fold and the reload
        // go into the "…", and the two arrows and the "…" are the row.
        let narrowest = plan(Metrics.sideMin, lights: corner(Metrics.sideMin))
        XCTAssertFalse(narrowest.fold)
        XCTAssertEqual(narrowest.doors, [.back, .forward])
        XCTAssertTrue(narrowest.more)
        XCTAssertLessThanOrEqual(narrowest.width, Metrics.sideMin - 2 * SideBand.pad - corner(Metrics.sideMin))
    }

    func testTheMoreIsAlwaysThereWhenSomethingGaveWay() {
        for column in stride(from: Metrics.sideMin, through: wholeRow, by: 1) {
            let plan = plan(column, lights: corner(column))
            let whole = plan.fold && plan.doors.count == HelmDoor.allCases.count && !plan.more
            XCTAssertEqual(whole, column >= wholeRow, "at \(column)")
            XCTAssertLessThanOrEqual(plan.width, column - 2 * SideBand.pad - corner(column), "at \(column)")
        }
    }

    func testFullScreenHasTheLightsCornerToSpend() {
        // Nothing in the lights' corner, so the whole row fits at a width
        // where a window's own column would have given the fold up.
        let plan = plan(Metrics.sideMin, lights: 0)
        XCTAssertTrue(plan.fold)
        XCTAssertEqual(plan.doors, HelmDoor.allCases)
        XCTAssertFalse(plan.more)
    }
}
