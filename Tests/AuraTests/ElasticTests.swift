import XCTest
@testable import Aura

/// The numbers the page leans by, kept where they can be read: they are
/// Chromium's (see Elastic.swift), and the bench's synthesized scroll deltas
/// are not in the unit a trackpad's are, so this is the place the share can be
/// checked exactly.
final class ElasticTests: XCTestCase {
    func testNothingMovesForTheFirstTenPoints() {
        XCTAssertEqual(Elastic.stretch(0, in: 1000), 0)
        XCTAssertEqual(Elastic.stretch(9, in: 1000), 0)
        XCTAssertEqual(Elastic.stretch(10, in: 1000), 0)
    }

    func testATwentiethOfWhatTheFingersTravel() {
        // kRubberbandStiffness: 300 points of fingers, 14.5 of page.
        XCTAssertEqual(Elastic.stretch(300, in: 1000), 14.5, accuracy: 0.001)
        XCTAssertEqual(Elastic.stretch(210, in: 1000), 10, accuracy: 0.001)
    }

    func testNoLeanPastAThirdOfThePage() {
        XCTAssertEqual(Elastic.stretch(100_000, in: 900), 300, accuracy: 0.001)
        XCTAssertEqual(Elastic.stretch(50, in: 0), 0, "a page with no width has nothing to lean")
    }

    func testTheWayHomeIsUnderAPointWithinAFractionOfASecond() {
        // Chromium's decay: exp(-t · stiffness / period), 12.5 a second.
        for lean in [1.0, 15, 120, 300] {
            let t = Elastic.settles(from: CGFloat(lean))
            let left = Double(lean) * exp(-t * 12.5)
            XCTAssertLessThan(left, 1.2, "a lean of \(lean) still had \(left) at \(t)s")
            XCTAssertLessThanOrEqual(t, 0.6)
        }
        XCTAssertGreaterThan(Elastic.settles(from: 300), Elastic.settles(from: 10))
    }
}
