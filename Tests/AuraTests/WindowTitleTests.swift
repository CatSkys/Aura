import XCTest
@testable import Aura

@MainActor
final class WindowTitleTests: XCTestCase {
    func testWindowIsNamedForItsPage() {
        XCTAssertEqual(WindowTitle.name(page: "Example Domain", private: false), "Example Domain")
        XCTAssertEqual(WindowTitle.name(page: "  Example Domain \n", private: false), "Example Domain")
    }

    func testWindowWithoutAPageTitleIsNamedForTheApp() {
        XCTAssertEqual(WindowTitle.name(page: "", private: false), "Aura")
        XCTAssertEqual(WindowTitle.name(page: "   ", private: false), "Aura")
    }

    func testPrivateTabNeverGivesItsPageAway() {
        XCTAssertEqual(WindowTitle.name(page: "Something personal", private: true), "Private Tab")
    }
}
