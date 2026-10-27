import XCTest
@testable import Aura

/// A conversation read back from the file the last build wrote: the fields
/// this one adds are what a line was without, and never the reason a whole
/// list of conversations comes back empty.
@MainActor
final class ChatRecordTests: XCTestCase {
    /// A line as a build from before `carried`, `steps` and `addressed`
    /// wrote one.
    private let older = """
    {
      "id": "8B1B0A0E-9A1B-4C0D-8E3F-0A1B2C3D4E5F",
      "mine": true,
      "text": "Which file holds the theme colours?",
      "done": true,
      "at": 780000000,
      "page": "Aura",
      "strays": ["example.com"]
    }
    """

    func testALineFromAnOlderBuildStillReads() throws {
        let line = try JSONDecoder().decode(Chat.Line.self, from: Data(older.utf8))
        XCTAssertTrue(line.mine)
        XCTAssertEqual(line.text, "Which file holds the theme colours?")
        XCTAssertEqual(line.strays, ["example.com"])
        // What it never had, it is without.
        XCTAssertTrue(line.carried.isEmpty)
        XCTAssertTrue(line.steps.isEmpty)
        XCTAssertFalse(line.addressed)
        XCTAssertEqual(line.shots, 0)
    }

    func testWhatAQuestionCarriedGoesRoundAgain() throws {
        let line = Chat.Line(mine: true, text: "What is this?",
                             carried: [Chat.Carried(kind: .page, title: "Example Domain",
                                                    detail: "example.com",
                                                    address: "https://example.com/")])
        let back = try JSONDecoder().decode(Chat.Line.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(back.carried, line.carried)
        XCTAssertEqual(back.carried.first?.kind, .page)
        XCTAssertEqual(back.carried.first?.title, "Example Domain")
    }

    func testAConversationOfLinesReadsWhole() throws {
        let record = """
        [{"id": "3F0B7C3A-1111-4222-8333-444455556666", "title": "Summary · Example Domain",
          "at": 780000000, "updated": 780000100, "provider": "openAI", "model": "gpt-4o-mini",
          "lines": [\(older)]}]
        """
        let records = try JSONDecoder().decode([Chat.Record].self, from: Data(record.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.lines.count, 1)
        XCTAssertEqual(records.first?.lines.first?.text, "Which file holds the theme colours?")
    }
}
