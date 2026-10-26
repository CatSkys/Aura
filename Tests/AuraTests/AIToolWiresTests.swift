import XCTest
@testable import Aura

/// Reading a tool call back out of each provider's stream, and writing one
/// back into the history in the shape that provider wants. The three wires
/// send the same call three ways; this is what says they end up the same call.
@MainActor
final class AIToolWiresTests: XCTestCase {
    // MARK: - the declaration

    func testEveryToolIsDeclaredTheSameThreeWays() throws {
        let tool = try XCTUnwrap(AITool.named("click"))
        let schema = AIToolWires.parameters(tool)
        XCTAssertEqual(schema["type"] as? String, "object")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["ref"])
        XCTAssertNotNil(properties["say"])
        XCTAssertEqual(schema["required"] as? [String], ["ref", "say"])

        let openAI = try XCTUnwrap(AIToolWires.openAI([tool]))
        let function = try XCTUnwrap(openAI.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "click")

        let anthropic = try XCTUnwrap(AIToolWires.anthropic([tool]))
        XCTAssertNotNil(anthropic.first?["input_schema"])

        let gemini = try XCTUnwrap(AIToolWires.gemini([tool]))
        let declared = try XCTUnwrap(gemini.first?["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declared.first?["name"] as? String, "click")
    }

    func testNoToolsMeansNothingInTheRequest() {
        XCTAssertNil(AIToolWires.openAI([]))
        XCTAssertNil(AIToolWires.anthropic([]))
        XCTAssertNil(AIToolWires.gemini([]))
    }

    func testAChoiceListIsAnEnumInTheSchema() throws {
        let tool = try XCTUnwrap(AITool.named("tabs"))
        let properties = try XCTUnwrap(AIToolWires.parameters(tool)["properties"] as? [String: Any])
        let action = try XCTUnwrap(properties["action"] as? [String: Any])
        XCTAssertEqual(action["enum"] as? [String], ["list", "open", "select", "close"])
    }

    // MARK: - reading a call

    func testOpenAICallsAreStitchedFromTheirFragments() {
        var reader = AIToolWires.Reader(.openAI)
        // Two calls at once, their argument fragments interleaved — which is
        // exactly how OpenAI sends them.
        let events: [[String: Any]] = [
            ["choices": [["delta": ["tool_calls": [["index": 0, "id": "call_a",
                                                   "function": ["name": "click", "arguments": ""]]]]]]],
            ["choices": [["delta": ["tool_calls": [["index": 1, "id": "call_b",
                                                   "function": ["name": "set_value", "arguments": ""]]]]]]],
            ["choices": [["delta": ["tool_calls": [["index": 0,
                                                   "function": ["arguments": #"{"ref": "3","#]]]]]]],
            ["choices": [["delta": ["tool_calls": [["index": 1,
                                                   "function": ["arguments": #"{"ref": "5","#]]]]]]],
            ["choices": [["delta": ["tool_calls": [["index": 0,
                                                   "function": ["arguments": #""say": "Clicking"}"#]]]]]]],
            ["choices": [["delta": ["tool_calls": [["index": 1,
                                                   "function": ["arguments": #""value": "hi", "say": "Typing"}"#]]]]]]],
        ]
        for event in events { XCTAssertTrue(reader.read(event).isEmpty) }
        let calls = reader.finished()
        XCTAssertEqual(calls.map(\.id), ["call_a", "call_b"])
        XCTAssertEqual(calls.map(\.name), ["click", "set_value"])
        XCTAssertEqual(calls[0].arguments, #"{"ref": "3","say": "Clicking"}"#)
        XCTAssertEqual(calls[1].arguments, #"{"ref": "5","value": "hi", "say": "Typing"}"#)
        XCTAssertTrue(reader.finished().isEmpty, "a finished reader is spent")
    }

    func testAnthropicCallsAreStitchedFromTheirDeltas() {
        var reader = AIToolWires.Reader(.anthropic)
        XCTAssertTrue(reader.read(["type": "content_block_start",
                                   "content_block": ["type": "tool_use", "id": "toolu_1", "name": "press",
                                                     "input": [:]]]).isEmpty)
        _ = reader.read(["type": "content_block_delta",
                         "delta": ["type": "input_json_delta", "partial_json": #"{"key": "Ent"#]])
        _ = reader.read(["type": "content_block_delta",
                         "delta": ["type": "input_json_delta", "partial_json": #"er", "say": "Pressing"}"#]])
        let calls = reader.finished()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "toolu_1")
        XCTAssertEqual(calls.first?.name, "press")
        XCTAssertEqual(calls.first?.arguments, #"{"key": "Enter", "say": "Pressing"}"#)
    }

    func testAnthropicAtoolWithNoArgumentsSendsAnEmptyObject() {
        var reader = AIToolWires.Reader(.anthropic)
        _ = reader.read(["type": "content_block_start",
                         "content_block": ["type": "tool_use", "id": "toolu_2", "name": "read",
                                           "input": [String: Any]()]])
        XCTAssertEqual(reader.finished().first?.arguments, "{}")
    }

    func testGeminiCallsArriveWhole() {
        var reader = AIToolWires.Reader(.gemini)
        _ = reader.read(["candidates": [["content": ["parts": [
            ["functionCall": ["name": "navigate", "args": ["url": "https://example.com/", "say": "Opening"]]],
        ]]]]])
        let calls = reader.finished()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "navigate")
        let arguments = AIToolArguments(text: calls[0].arguments)
        XCTAssertEqual(arguments.string("url"), "https://example.com/")
        // Gemini gives no id, so one is made: the result that answers it has
        // to say which call it answers.
        XCTAssertFalse(calls[0].id.isEmpty)
    }

    func testAPieceOfACallWithNoNameIsNotACall() {
        var reader = AIToolWires.Reader(.openAI)
        _ = reader.read(["choices": [["delta": ["tool_calls": [["index": 0,
                                                               "function": ["arguments": #"{"ref": "1"}"#]]]]]]])
        XCTAssertTrue(reader.finished().isEmpty)
    }

    // MARK: - writing one back

    func testAWholeCallGoesBackInEachShape() {
        let call = AIToolWires.Call(id: "c1", name: "click", arguments: #"{"ref": "4", "say": "Clicking"}"#)

        let openAI = AIToolWires.assistant(.openAI, text: "One moment.", calls: [call]) as? [String: Any]
        XCTAssertEqual(openAI?["role"] as? String, "assistant")
        XCTAssertEqual(openAI?["content"] as? String, "One moment.")
        let toolCalls = openAI?["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.first?["id"] as? String, "c1")

        let anthropic = AIToolWires.assistant(.anthropic, text: "One moment.", calls: [call]) as? [[String: Any]]
        XCTAssertEqual(anthropic?.first?["type"] as? String, "text")
        let block = anthropic?.last
        XCTAssertEqual(block?["type"] as? String, "tool_use")
        // Anthropic wants the input as an object, not a string of JSON.
        XCTAssertEqual((block?["input"] as? [String: Any])?["ref"] as? String, "4")

        let gemini = AIToolWires.assistant(.gemini, text: "", calls: [call]) as? [[String: Any]]
        XCTAssertEqual(gemini?.count, 1)
        XCTAssertNotNil(gemini?.first?["functionCall"])
    }

    func testResultsAreATurnOfTheirOwnExceptOnAnthropic() {
        // Anthropic puts a tool's result in a user turn as a block; the other
        // two treat a result as a message of its own kind.
        XCTAssertFalse(AIToolWires.resultsAreTheirOwnMessage(.anthropic))
        XCTAssertTrue(AIToolWires.resultsAreTheirOwnMessage(.openAI))
        XCTAssertTrue(AIToolWires.resultsAreTheirOwnMessage(.gemini))
    }

    // MARK: - a history a provider will read

    private func call(_ id: String) -> AIToolWires.Call {
        AIToolWires.Call(id: id, name: "snapshot", arguments: #"{"say": "Reading"}"#)
    }

    private func answered(_ id: String) -> AIToolResult {
        AIToolResult(id: id, name: "snapshot", content: "read", isError: false)
    }

    func testACallAndItsAnswerAreKeptTogether() {
        let history = [
            AIMessage(role: .user, text: "What is this?"),
            AIMessage(role: .assistant, text: "", calls: [call("c1")]),
            AIMessage(role: .user, text: "", results: [answered("c1")]),
            AIMessage(role: .assistant, text: "A page about trains."),
        ]
        XCTAssertEqual(AIMessage.paired(history), history)
    }

    func testACallNothingAnsweredIsTakenOutWithItsAsk() {
        // What a turn that ended mid-way used to leave behind: the provider
        // refuses every request after it ("must be followed by tool
        // messages"), so the conversation is put back together rather than
        // left broken.
        let history = [
            AIMessage(role: .user, text: "What is this?"),
            AIMessage(role: .assistant, text: "", calls: [call("c1")]),
            AIMessage(role: .user, text: "", results: [answered("c1")]),
            AIMessage(role: .assistant, text: "Half an answ"),
            AIMessage(role: .assistant, text: "", calls: [call("c2")]),
        ]
        XCTAssertEqual(AIMessage.paired(history), [
            AIMessage(role: .user, text: "What is this?"),
            AIMessage(role: .assistant, text: "", calls: [call("c1")]),
            AIMessage(role: .user, text: "", results: [answered("c1")]),
            AIMessage(role: .assistant, text: "Half an answ"),
        ])
    }

    func testABatchIsAnsweredOnceForEveryCallInIt() {
        let history = [
            AIMessage(role: .assistant, text: "", calls: [call("c1"), call("c2")]),
            AIMessage(role: .user, text: "", results: [answered("c1")]),
            AIMessage(role: .assistant, text: "Done."),
        ]
        // One result for two calls leaves the second one refused by every
        // provider: the call goes, and what came of it goes with it.
        XCTAssertEqual(AIMessage.paired(history), [AIMessage(role: .assistant, text: "Done.")])
    }

    func testAnAnswerToACallThatIsNotThereGoes() {
        let history = [
            AIMessage(role: .user, text: "", results: [answered("gone")]),
            AIMessage(role: .user, text: "Why is the sky blue?"),
        ]
        XCTAssertEqual(AIMessage.paired(history), [AIMessage(role: .user, text: "Why is the sky blue?")])
    }
}
