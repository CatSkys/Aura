import XCTest
@testable import Aura

/// A tab's mute, written into the session (Session.Entry.muted, Browser's
/// session(_:active:groups:splits:) and restoreRow): a tab silenced by hand
/// comes back silenced, and a file written before the field reads as one that
/// was not — never as a file that won't decode, which would quarantine the
/// whole session and bring back not a single tab.
final class SessionMuteTests: XCTestCase {
    private func roundTrip(_ entry: Session.Entry) throws -> Session.Entry {
        let data = try JSONEncoder().encode(entry)
        return try JSONDecoder().decode(Session.Entry.self, from: data)
    }

    func testAMutedTabKeepsItsMuteInTheFile() throws {
        var entry = Session.Entry(url: "https://example.com/", title: "Example")
        entry.muted = true
        XCTAssertEqual(try roundTrip(entry).muted, true)
    }

    /// A tab that was never muted writes nothing for it at all.
    func testTheFieldIsLeftOutWhereItWasNeverMuted() throws {
        let entry = Session.Entry(url: "https://example.com/", title: "Example")
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        XCTAssertNil(raw?["muted"])
        XCTAssertNil(try roundTrip(entry).muted)
    }

    /// A session written before the field existed.
    func testAFileFromBeforeTheFieldReadsAsNotMuted() throws {
        let old = #"{"url":"https://example.com/","title":"Example"}"#
        let entry = try JSONDecoder().decode(Session.Entry.self, from: Data(old.utf8))
        XCTAssertNil(entry.muted)
        XCTAssertEqual(entry.url, "https://example.com/")
    }
}
