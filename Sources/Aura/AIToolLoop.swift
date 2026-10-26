import Foundation

// The loop that lets the model act: ask, take its tool calls, do them, answer
// it, ask again — the shape pi's agent loop has, with two hooks of our own.
//
// Two loops, because a conversation needs two:
//
//   while there is more to do:               ← the outer one waits for you
//     while the model asks for tools:        ← the inner one does them
//       ask the model, a piece at a time
//       if it asked for tools, do them, and answer it with what happened
//
// A single call runs through eight steps, and never throws:
//
//   1. find the tool by its name         — no such tool? an error result
//   2. read its arguments                — unreadable JSON? an error result
//   3. check them against the schema     — one missing? an error result
//   3.5 take `say`                       — it goes on the panel's pulse row
//   4. ask whether it may happen         — refused? an error result, and
//                                          the batch ends
//   5. stop if we were told to
//   6. run it                            — a throw is an error result too
//   7. take `did` from the result
//   7.5 hand `did` back as the record    — the panel is told it
//   8. never reject
//
// Step 8 is the whole point: a failure is something the model reads and can
// correct, not an exception thrown at the caller. A model told "ref 12 has
// gone, take a new snapshot" fixes itself; one only told that the request
// failed cannot.
//
// The one thing that does stop the batch is the person: a refused
// confirmation ends the turn, and nothing else the model asked for in that
// batch happens.

@MainActor
enum AIToolLoop {
    /// What the loop says as it goes, to whoever is drawing it: the words as
    /// they stream, the model's line for you, and the record of what was done.
    enum Event {
        /// A piece of the answer, as it arrives.
        case wrote(String)
        /// The model's own line for you, for the panel's pulse row.
        case saying(String)
        /// One call, done, as the record says it.
        case did(String)
        /// The person said no, and the turn ended there.
        case refused
    }

    /// How many rounds a turn may take: a model that keeps asking for tools
    /// and never answers is not interesting past this.
    static let rounds = 12

    /// One turn: the question is already in `messages`, and this adds the
    /// answer, the calls the answer made, and the results of those calls,
    /// until the model answers without asking for another.
    ///
    /// `check` is asked before each call and returns nil to allow it, or why
    /// it may not happen (see AIToolRisk).
    /// `messages` is what the conversation has said so far; what comes back
    /// is what this turn added, in order — the caller appends it once, so a
    /// failed turn leaves the history it started with.
    static func run(messages: [AIMessage], provider: AIProvider, model: String,
                    system: String, key: String?, tools: [AITool.Definition],
                    browser: Browser, tab: Tab,
                    stopped: @escaping () -> Bool,
                    check: @escaping (AITool.Definition, AIToolArguments) async -> AIToolRisk.Verdict,
                    event: @escaping (Event) -> Void) async throws -> [AIMessage] {
        var history = messages
        guard !tools.isEmpty else {
            // No tools at all: the plain stream, as it always was.
            let added = try await once(messages: messages, provider: provider, model: model,
                                       system: system, key: key, event: event)
            return added
        }
        var added: [AIMessage] = []
        for _ in 0..<rounds {
            if stopped() { return added }
            var said = ""
            var calls: [AIToolWires.Call] = []
            var cut = false
            let stream = AIClient.shared.stream(provider, model: model, system: system,
                                                messages: history, key: key, tools: tools) { call in
                calls.append(call)
            }
            do {
                for try await piece in stream {
                    said += piece
                    // A model talked into writing on and on is stopped, and
                    // what it had written by then is not a turn to keep.
                    if said.count > Chat.longest { cut = true; break }
                    event(.wrote(piece))
                }
            } catch {
                if !said.isEmpty { keep(AIMessage(role: .assistant, text: said), in: &history, &added) }
                throw error
            }
            if stopped() {
                if !said.isEmpty { keep(AIMessage(role: .assistant, text: said), in: &history, &added) }
                return added
            }
            guard !calls.isEmpty else {
                keep(AIMessage(role: .assistant, text: said), in: &history, &added)
                // It answered without asking for anything: the turn is done.
                return added
            }
            keep(AIMessage(role: .assistant, text: said, calls: calls), in: &history, &added)
            // A turn cut off mid-sentence has half-written tool arguments, and
            // running those would be running half an instruction. Every call
            // in that message fails, unread (pi's rule).
            var results: [AIToolResult] = []
            var personSaidNo = false
            for call in calls {
                if personSaidNo || stopped() { break }
                let outcome = cut
                    ? AITool.Outcome(one: .failed("The answer was cut off before this call finished, so it was not run. If there were many calls at once, ask for fewer."))
                    : await one(call, tools: tools, browser: browser, tab: tab, stopped: stopped, check: check, event: event)
                if outcome.refused { personSaidNo = true; event(.refused) }
                results.append(AIToolResult(id: call.id, name: call.name,
                                            content: outcome.result.content, isError: outcome.result.isError))
                if !outcome.result.did.isEmpty { event(.did(outcome.result.did)) }
            }
            keep(AIMessage(role: .user, text: "", results: results), in: &history, &added)
            // A picture a tool took can't ride in a tool result on any of the
            // three wires, so it follows as an ordinary turn's picture.
            let shots = takenPictures()
            if !shots.isEmpty, let last = added.indices.last {
                added[last].images += shots
                history[history.count - 1].images += shots
            }
            if personSaidNo || stopped() { return added }
        }
        return added
    }

    /// A message this turn added, in both lists: the history the next round
    /// is asked with, and the answer the caller keeps.
    private static func keep(_ message: AIMessage, in history: inout [AIMessage], _ added: inout [AIMessage]) {
        history.append(message)
        added.append(message)
    }

    /// The plain answer, for a conversation with no tools: the stream as it
    /// always ran.
    private static func once(messages: [AIMessage], provider: AIProvider, model: String,
                             system: String, key: String?, event: @escaping (Event) -> Void) async throws -> [AIMessage] {
        var said = ""
        let stream = AIClient.shared.stream(provider, model: model, system: system,
                                            messages: messages, key: key)
        for try await piece in stream {
            said += piece
            if said.count > Chat.longest { break }
            event(.wrote(piece))
        }
        return [AIMessage(role: .assistant, text: said)]
    }

    /// A single call, through the eight steps. Never throws.
    private static func one(_ call: AIToolWires.Call, tools: [AITool.Definition],
                            browser: Browser, tab: Tab, stopped: @escaping () -> Bool,
                            check: @escaping (AITool.Definition, AIToolArguments) async -> AIToolRisk.Verdict,
                            event: @escaping (Event) -> Void) async -> AITool.Outcome {
        // 1. the tool
        guard let tool = tools.first(where: { $0.name == call.name }) ?? AITool.named(call.name) else {
            return AITool.Outcome(one: .failed("There's no tool called “\(call.name)”. The ones there are: \(tools.map(\.name).joined(separator: ", "))."))
        }
        // 2. its arguments
        let arguments = AIToolArguments(text: call.arguments)
        // 3. the schema, `say` included, because it is a required field there
        if let wrong = arguments.checked(against: tool.schema) {
            return AITool.Outcome(one: .failed("\(tool.name): \(wrong)"))
        }
        // 3.5 the model's own line for you
        let say = arguments.string("say") ?? ""
        if tool.says {
            guard !say.isEmpty else {
                return AITool.Outcome(one: .failed("\(tool.name): the argument “say” is required — one short line for the person watching, in the present tense, saying what this call does."))
            }
            event(.saying(say))
        }
        // 4. whether it may happen
        if case .refused(let why) = await check(tool, arguments) {
            return AITool.Outcome(one: .failed(why), refused: true)
        }
        // 5. and whether we were told to stop
        if stopped() { return AITool.Outcome(one: .failed("The person stopped this before it ran.")) }
        // 6 and 7: doing it. A throw here is caught inside the tool, so this
        // is a result either way.
        let context = AITool.Context(browser: browser, tab: tab, say: say, stopped: stopped)
        let result = await tool.run(arguments, context)
        return AITool.Outcome(one: result)
    }

    // MARK: - a picture on its way

    /// A screenshot's picture, waiting for the turn that carries it: kept here
    /// because a tool result can't hold one, and the next user turn can.
    private static var shots: [Data] = []

    static func keep(_ data: Data) {
        shots.append(data)
        if shots.count > 4 { shots.removeFirst(shots.count - 4) }
    }

    /// What was pictured since the last turn was written, spent.
    private static func takenPictures() -> [Data] {
        let found = shots
        shots = []
        return found
    }
}
