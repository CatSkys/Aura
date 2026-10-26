import Foundation

// One tool declaration, written the three ways the providers understand it,
// and one tool call read back out of each of their streams.
//
// This file exists because there is no provider abstraction here and there
// will not be one (AIClient's own words): three shapes of request are written
// by hand, so the tool half of each shape is written by hand too — but from
// one declaration (AITool.Definition), so a tool added once is offered by all
// three, and a call parsed once is parsed the same way whichever answered.
//
// What differs, and what this file hides:
//
//   · OpenAI wraps tools as `{"type": "function", "function": {…}}`, sends
//     arguments as a JSON *string*, and streams them in fragments that have to
//     be stitched together by index;
//   · Anthropic sends `input` as an object, opens a `tool_use` block with an
//     id, and streams its arguments as `input_json_delta` pieces;
//   · Gemini has `functionDeclarations`, sends `args` as an object, and
//     answers with whole `functionCall` parts rather than pieces of one.
//
// An id is the one thing Gemini doesn't give: a call is made one here, so the
// result that answers it can say which call it answers.

enum AIToolWires {
    // MARK: - the declaration

    /// A tool's schema as JSON Schema, which all three understand — the one
    /// shape they agree on.
    static func parameters(_ tool: AITool.Definition) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (name, property) in tool.schema.properties {
            var one: [String: Any] = ["type": property.kind.rawValue, "description": property.description]
            if !property.choices.isEmpty { one["enum"] = property.choices }
            properties[name] = one
        }
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !tool.schema.required.isEmpty { schema["required"] = tool.schema.required }
        return schema
    }

    /// The tools, for OpenAI's chat completions (and everything that speaks
    /// its shape) — nil when there are none, so the request carries nothing.
    static func openAI(_ tools: [AITool.Definition]) -> [[String: Any]]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            ["type": "function",
             "function": ["name": tool.name, "description": tool.description, "parameters": parameters(tool)]]
        }
    }

    /// The tools, for Anthropic's messages.
    static func anthropic(_ tools: [AITool.Definition]) -> [[String: Any]]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            ["name": tool.name, "description": tool.description, "input_schema": parameters(tool)]
        }
    }

    /// The tools, for Gemini's generateContent.
    static func gemini(_ tools: [AITool.Definition]) -> [[String: Any]]? {
        guard !tools.isEmpty else { return nil }
        return [["functionDeclarations": tools.map { tool in
            ["name": tool.name, "description": tool.description, "parameters": parameters(tool)]
        }]]
    }

    // MARK: - reading a call

    /// One call, as it comes out of a stream: the id the result will answer,
    /// the tool's name, and its arguments as the JSON string every provider
    /// can be read down to.
    struct Call: Equatable {
        let id: String
        let name: String
        let arguments: String
    }

    /// A stream's tool calls, stitched together while it runs.
    ///
    /// One reader per answer. OpenAI and Anthropic send a call in pieces —
    /// the name once, then arguments a fragment at a time — so the pieces are
    /// kept by index and given back whole when the answer ends. Gemini sends
    /// whole calls, which are simply collected.
    struct Reader {
        private let wire: AIProvider.Wire
        private var building: [Int: (id: String, name: String, arguments: String)] = [:]
        private var whole: [Call] = []

        init(_ wire: AIProvider.Wire) {
            self.wire = wire
        }

        /// This event's tool calls, if it has any worth handing on now. For
        /// the wires that send pieces this is empty until the answer ends —
        /// `finished()` is what gives them back.
        mutating func read(_ json: [String: Any]) -> [Call] {
            switch wire {
            case .openAI:
                let choice = (json["choices"] as? [[String: Any]])?.first
                // The batch's own index: a message can ask for several at
                // once, and their fragments interleave.
                for call in (choice?["delta"] as? [String: Any])?["tool_calls"] as? [[String: Any]] ?? [] {
                    let slot = call["index"] as? Int ?? 0
                    var held = building[slot] ?? ("", "", "")
                    if let id = call["id"] as? String, !id.isEmpty { held.id = id }
                    let function = call["function"] as? [String: Any]
                    if let name = function?["name"] as? String, !name.isEmpty { held.name += name }
                    if let piece = function?["arguments"] as? String { held.arguments += piece }
                    building[slot] = held
                }
                return []
            case .anthropic:
                guard json["type"] as? String == "content_block_start",
                      let block = json["content_block"] as? [String: Any],
                      block["type"] as? String == "tool_use",
                      let id = block["id"] as? String, let name = block["name"] as? String
                else {
                    // The arguments' own pieces, until the block closes.
                    if json["type"] as? String == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       delta["type"] as? String == "input_json_delta",
                       let piece = delta["partial_json"] as? String,
                       let slot = building.keys.first {
                        building[slot]?.arguments += piece
                    }
                    return []
                }
                let slot = building.count
                // An input that is already whole (a provider that doesn't
                // stream the arguments) is kept; an empty one is nothing yet,
                // because the pieces are still coming and prefixing them with
                // "{}" would make the JSON unreadable.
                let input = block["input"] as? [String: Any] ?? [:]
                let written = input.isEmpty ? ""
                    : (try? JSONSerialization.data(withJSONObject: input))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                building[slot] = (id, name, written)
                return []
            case .gemini:
                let candidate = (json["candidates"] as? [[String: Any]])?.first
                let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                for part in parts {
                    guard let call = part["functionCall"] as? [String: Any],
                          let name = call["name"] as? String
                    else { continue }
                    let arguments = call["args"] as? [String: Any] ?? [:]
                    let written = (try? JSONSerialization.data(withJSONObject: arguments))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    whole.append(Call(id: "call_" + UUID().uuidString.lowercased().prefix(8), name: name, arguments: written))
                }
                return []
            }
        }

        /// The calls the answer made, in the order it made them.
        mutating func finished() -> [Call] {
            var calls = building.sorted { $0.key < $1.key }.compactMap { _, held -> Call? in
                guard !held.name.isEmpty else { return nil }
                let id = held.id.isEmpty ? "call_" + UUID().uuidString.lowercased().prefix(8) : held.id
                let arguments = held.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                return Call(id: id, name: held.name, arguments: arguments.isEmpty ? "{}" : arguments)
            }
            calls += whole
            building = [:]
            whole = []
            return calls
        }
    }

    // MARK: - writing a call back

    /// A turn the model took, as each wire wants it said again in the history:
    /// the words it wrote and the calls it made, together in one message.
    static func assistant(_ wire: AIProvider.Wire, text: String, calls: [Call]) -> Any {
        switch wire {
        case .openAI:
            var message: [String: Any] = ["role": "assistant"]
            if !text.isEmpty { message["content"] = text }
            if !calls.isEmpty {
                message["tool_calls"] = calls.enumerated().map { index, call in
                    ["id": call.id, "type": "function", "index": index,
                     "function": ["name": call.name, "arguments": call.arguments]]
                }
            }
            return message
        case .anthropic:
            var blocks: [[String: Any]] = []
            if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
            for call in calls {
                let input = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
                blocks.append(["type": "tool_use", "id": call.id, "name": call.name, "input": input])
            }
            return blocks
        case .gemini:
            var parts: [[String: Any]] = []
            if !text.isEmpty { parts.append(["text": text]) }
            for call in calls {
                let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
                parts.append(["functionCall": ["name": call.name, "args": args]])
            }
            return parts
        }
    }

    /// A tool's result, as each wire wants it said: OpenAI and Anthropic have
    /// a message of their own for one, Gemini a part inside the next turn.
    static func result(_ wire: AIProvider.Wire, id: String, name: String, content: String, isError: Bool) -> Any {
        switch wire {
        case .openAI:
            return ["role": "tool", "tool_call_id": id, "content": content]
        case .anthropic:
            return ["type": "tool_result", "tool_use_id": id, "content": content, "is_error": isError]
        case .gemini:
            var response: [String: Any] = ["output": content]
            if isError { response["error"] = content }
            return ["functionResponse": ["name": name, "response": response]]
        }
    }

    /// Whether this wire says a turn's results as messages of their own
    /// (OpenAI, Gemini) or inside the next turn (Anthropic, which puts
    /// `tool_result` blocks in a user message).
    static func resultsAreTheirOwnMessage(_ wire: AIProvider.Wire) -> Bool {
        wire != .anthropic
    }
}
