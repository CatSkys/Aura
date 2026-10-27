import XCTest
@testable import Aura

/// A tool call's arguments: the reader the tools use, and the schema check
/// that stands between a model's guess and half a call attempted (AIToolLoop's
/// third step). Nothing here touches a page.
@MainActor
final class AIToolArgumentsTests: XCTestCase {
    private func arguments(_ text: String) -> AIToolArguments { AIToolArguments(text: text) }

    func testValuesComeOutAsTheToolsAskForThem() {
        let read = arguments(#"{"ref": 12, "value": "hello", "submit": true, "pages": 2.5}"#)
        XCTAssertEqual(read.string("ref"), "12")
        XCTAssertEqual(read.string("value"), "hello")
        XCTAssertNil(read.string("missing"))
        XCTAssertEqual(read.number("pages"), 2.5)
        XCTAssertEqual(read.number("value"), nil)
        XCTAssertTrue(read.bool("submit"))
        XCTAssertFalse(read.bool("page"))
    }

    func testBooleanTextIsReadAsABoolean() {
        XCTAssertTrue(arguments(#"{"full": "true"}"#).bool("full"))
        XCTAssertTrue(arguments(#"{"full": 1}"#).bool("full"))
        XCTAssertFalse(arguments(#"{"full": "yes"}"#).bool("full"))
    }

    func testEmptyTextIsAnEmptyObjectNotAFailure() {
        // Anthropic sends "{}" for a tool with no arguments, and OpenAI sends
        // an empty string at the end of a call stream: neither is malformed.
        for text in ["", "{}", "  \n " ] {
            let read = arguments(text)
            XCTAssertNil(read.checked(against: AITool.Schema()), text)
        }
    }

    func testTextThatIsNotAnObjectIsMalformed() {
        for text in ["not json", "[1, 2]", #""a string""#] {
            let read = arguments(text)
            XCTAssertNotNil(read.checked(against: AITool.Schema()), text)
        }
    }

    func testMissingRequiredArgumentSaysWhichOne() throws {
        let tool = try XCTUnwrap(AITool.named("click"))
        let wrong = arguments(#"{"say": "Clicking it"}"#)
        let why = try XCTUnwrap(wrong.checked(against: tool.schema))
        XCTAssertTrue(why.contains("ref"), why)
    }

    func testAChoiceOutsideTheListIsRefused() throws {
        let tool = try XCTUnwrap(AITool.named("scroll"))
        let wrong = arguments(#"{"say": "Scrolling", "direction": "sideways"}"#)
        let why = try XCTUnwrap(wrong.checked(against: tool.schema))
        XCTAssertTrue(why.contains("direction"), why)
        XCTAssertTrue(why.contains("up"), why)
        XCTAssertNil(arguments(#"{"say": "Scrolling", "direction": "up"}"#).checked(against: tool.schema))
    }

    func testAValueOfTheWrongKindIsRefused() throws {
        let tool = try XCTUnwrap(AITool.named("snapshot"))
        XCTAssertNotNil(arguments(#"{"full": "often"}"#).checked(against: tool.schema))
        XCTAssertNil(arguments(#"{"full": "true"}"#).checked(against: tool.schema))
    }

    func testAnExtraArgumentIsNotAFailedCall() throws {
        // Nothing is done with it either way, and a model given a failed call
        // for a field it invented learns the wrong lesson.
        let tool = try XCTUnwrap(AITool.named("back"))
        XCTAssertNil(arguments(#"{"say": "Going back", "why": "because"}"#).checked(against: tool.schema))
    }

    func testEveryToolAsksForItsLine() {
        // `say` is on every tool, not only the ones that change something:
        // it is the row the rail keeps for the call, in the model's own words
        // (AIToolStep), so reading a page says what it read rather than
        // "Read the page" once more.
        for tool in AITool.all {
            let asked = AIToolWires.parameters(tool)
            let properties = asked["properties"] as? [String: Any] ?? [:]
            XCTAssertNotNil(properties["say"], "\(tool.name) is not asked for its line")
            XCTAssertTrue((asked["required"] as? [String])?.contains("say") == true,
                          "\(tool.name) does not require say")
        }
    }

    func testEveryToolIsNamedOnceAndHasADescription() {
        let names = AITool.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "a tool is declared twice")
        for tool in AITool.all {
            XCTAssertFalse(tool.description.isEmpty, tool.name)
            XCTAssertNotNil(AITool.named(tool.name))
        }
    }
}
