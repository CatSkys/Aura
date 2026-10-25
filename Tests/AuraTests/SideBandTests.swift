import XCTest
@testable import Aura

/// What the column's band holds at a given width (SideBand.swift): the fold
/// and the three doors while there is room, and a "…" for whatever gave way.
final class SideBandTests: XCTestCase {
    /// A window not in full screen has the lights' corner beside the band.
    private let lights = Metrics.sideLights

    private func plan(_ column: CGFloat, lights: CGFloat? = nil) -> SideBand.Plan {
        SideBand.plan(column: column, lights: lights ?? self.lights)
    }

    func testTheWholeRowWhileItFits() {
        let wide = plan(Metrics.side)
        XCTAssertTrue(wide.fold)
        XCTAssertEqual(wide.doors, HelmDoor.allCases)
        XCTAssertFalse(wide.more)
        XCTAssertEqual(wide.gap, SideBand.wide)
    }

    func testTheFoldAndTheAirAreWhatGiveWayFirst() {
        // 208 across: the room the four doors and their gaps take, exactly.
        let exactly = plan(208)
        XCTAssertTrue(exactly.fold)
        XCTAssertFalse(exactly.more)

        // A point narrower, the row closes up and the fold goes into the "…":
        // the arrows, the ones reached for most, stay.
        let tight = plan(207)
        XCTAssertFalse(tight.fold)
        XCTAssertEqual(tight.doors, [.back, .forward, .reload])
        XCTAssertTrue(tight.more)
        XCTAssertEqual(tight.gap, SideBand.tight)
    }

    func testTheArrowsStayAtTheColumnsNarrowest() {
        // 176 across, the narrowest the column goes: the fold and the reload
        // go into the "…", and the two arrows and the "…" are the row.
        let narrowest = plan(Metrics.sideMin)
        XCTAssertFalse(narrowest.fold)
        XCTAssertEqual(narrowest.doors, [.back, .forward])
        XCTAssertTrue(narrowest.more)
        XCTAssertLessThanOrEqual(narrowest.width, Metrics.sideMin - 2 * SideBand.pad - lights)
    }

    func testTheMoreIsAlwaysThereWhenSomethingGaveWay() {
        for column in stride(from: Metrics.sideMin, through: 208, by: 1) {
            let plan = plan(column)
            let whole = plan.fold && plan.doors.count == HelmDoor.allCases.count && !plan.more
            XCTAssertEqual(whole, column >= 208, "at \(column)")
            XCTAssertLessThanOrEqual(plan.width, column - 2 * SideBand.pad - lights, "at \(column)")
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
