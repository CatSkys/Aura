import Foundation

// A tool call's arguments, as the model sent them.
//
// Every provider hands the arguments over as a string of JSON — OpenAI and
// Gemini as a whole object, Anthropic as the text of a `tool_use` block — so
// they arrive here as that string and are read once. What comes out is a
// small, read-only view with the two things that matter:
//
//   · a reader for each type that the tools ask for, which says nil rather
//     than throwing when the value is missing or the wrong type;
//   · `checked`, which is the schema check of AIToolLoop's third step: a call
//     whose arguments don't fit the tool's schema is a failed call, said as a
//     result the model reads, never a call attempted halfway.
//
// The check is written by hand because there is no JSON Schema library here
// and there will not be one: what the tools need is objects with named
// properties, of four kinds, some required, and a few with a list of words to
// choose from. That is a hundred lines, not a dependency.

struct AIToolArguments {
    /// The arguments as they were sent, kept for the record and for a
    /// provider that wants them handed back verbatim (Anthropic's input).
    let raw: [String: Any]
    /// What the model wrote, or what was read out of the string. Empty when
    /// the arguments were not JSON at all, which `checked` reports.
    private(set) var malformed = false

    init(_ raw: [String: Any]) {
        self.raw = raw
    }

    /// A call's arguments, out of the string each provider sends.
    init(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            raw = [:]
            return
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            raw = [:]
            malformed = true
            return
        }
        raw = object
    }

    static let empty = AIToolArguments([:])

    func string(_ key: String) -> String? {
        switch raw[key] {
        case let text as String: return text.isEmpty ? nil : text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    func number(_ key: String) -> Double? {
        switch raw[key] {
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool {
        switch raw[key] {
        case let number as NSNumber: return number.boolValue
        case let text as String: return text == "true" || text == "1"
        default: return false
        }
    }

    /// This call against the tool's schema: nil when it fits, and what is
    /// wrong when it doesn't. An extra argument is allowed — a model that
    /// writes one is not given a failed call for it, since nothing is done
    /// with it either way.
    func checked(against schema: AITool.Schema) -> String? {
        if malformed { return "The arguments were not a JSON object. Call the tool again with an object." }
        for name in schema.required {
            if raw[name] == nil || raw[name] is NSNull {
                return "The argument “\(name)” is required and was missing."
            }
        }
        for (name, property) in schema.properties {
            guard let value = raw[name], !(value is NSNull) else { continue }
            if !property.choices.isEmpty {
                guard let text = string(name), property.choices.contains(text) else {
                    return "The argument “\(name)” must be one of: \(property.choices.joined(separator: ", "))."
                }
                continue
            }
            switch property.kind {
            case .string:
                guard value is String || value is NSNumber else {
                    return "The argument “\(name)” must be text."
                }
            case .number:
                guard number(name) != nil else {
                    return "The argument “\(name)” must be a number."
                }
            case .boolean:
                guard value is NSNumber || value is Bool || (value as? String).map({ $0 == "true" || $0 == "false" }) == true else {
                    return "The argument “\(name)” must be true or false."
                }
            }
        }
        return nil
    }
}
