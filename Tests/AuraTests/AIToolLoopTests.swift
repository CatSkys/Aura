import AppKit
import Darwin
import XCTest
@testable import Aura

/// The loop itself, against a stand-in provider on this Mac: what the model is
/// sent, in what order, and what reaches the page.
///
/// The one thing this test exists for is a bug that passed every other check:
/// the loop kept the turn's messages in the answer it returned but asked the
/// next round with the history it started from, so the model never saw its own
/// tool results and asked again forever. A plain unit test of AITool cannot
/// see that, because nothing is wrong with any single call.
@MainActor
final class AIToolLoopTests: XCTestCase {
    private var server: MockProvider?
    private var pages: LocalPageServer?
    private var browser: Browser?
    private var tab: Tab?

    override class func setUp() {
        setenv("AURA_PROBE", "ai-tool-loop-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        AIProvider.mock = nil
        AIToolSnap.reset()
        AIToolAsk.confirming = .allow
    }

    override func tearDown() {
        AIProvider.mock = nil
        AIToolAsk.confirming = nil
        AIToolSnap.reset()
        server?.stop()
        server = nil
        pages?.stop()
        pages = nil
        super.tearDown()
    }

    /// A tool that needs no page: the loop is what is under test here, and a
    /// windowless run has no document for WebKit to snapshot (see the note on
    /// TabLoad in Bench: a snapshot of a page with neither a size nor a window
    /// is a snapshot of nothing). What the tools do to a page is
    /// AIToolSwift's own test and the probe's, not this one's.
    private func tools(_ answers: [String]) -> [AITool.Definition] {
        var left = answers
        return [AITool.Definition(
            name: "pretend", description: "A tool that does nothing but answer.",
            schema: AITool.Schema(properties: ["say": AITool.sayProperty], required: ["say"]),
            risk: .reading,
            run: { _, _ in
                let said = left.isEmpty ? "nothing left" : left.removeFirst()
                return .ok("pretended: " + said, detail: said)
            })]
    }

    /// The stand-in itself, before anything else is asked of it: a POST to it
    /// gets the first turn back. When this fails, the loop's tests say nothing
    /// about the loop.
    func testTheStandInProviderAnswers() async throws {
        let provider = try MockProvider(turns: [.words("hello")])
        server = provider
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(provider.port)/x")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let (data, response) = await (try? URLSession.shared.data(for: request)) ?? (Data(), nil)
        let said = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(said.contains("hello"), said + " / " + provider.failed)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    /// The messages of a request this mock was sent: what the model would
    /// have seen, as the one object it is.
    private static func messages(_ request: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(request["messages"] as? [[String: Any]])
    }

    /// A turn that asks for the tool twice, then answers: the model must be
    /// shown the result of each call before it is asked the next time. This is
    /// the bug a plain unit test of AITool cannot see — nothing was wrong with
    /// any single call, only with what the next round was asked with.
    func testTheModelIsShownEachToolsResultBeforeTheNextRound() async throws {
        let provider = try MockProvider(turns: [
            .calls([("call_1", "pretend", #"{"say": "First"}"#)]),
            .calls([("call_2", "pretend", #"{"say": "Second"}"#)]),
            .words("All done."),
        ])
        server = provider
        AIProvider.mock = try XCTUnwrap(URL(string: "http://127.0.0.1:\(provider.port)"))

        let browser = Browser(record: WindowRecord())
        self.browser = browser
        let tab = browser.benchOpen(try XCTUnwrap(URL(string: "about:blank")))
        self.tab = tab
        let said = tools(["one", "two"])

        var events: [AIToolLoop.Event] = []
        let added = try await AIToolLoop.run(
            messages: [AIMessage(role: .user, text: "Press the send button")],
            provider: .openAI, model: "test-model", system: "You are a test.",
            key: "sk-test-not-a-real-key", tools: said,
            browser: browser, tab: tab, stopped: { false },
            check: { _, _ in .allowed },
            event: { events.append($0) })

        // Three asks: the tool calls, the second tool call, the answer.
        XCTAssertEqual(provider.asks.count, 3)
        // The second ask carries the first call and its result.
        let second = try XCTUnwrap(provider.asks.dropFirst().first)
        let secondMessages = try Self.messages(second)
        let calls = secondMessages.compactMap { $0["tool_calls"] as? [[String: Any]] }
        XCTAssertEqual(calls.count, 1, "the model was not shown the call it made")
        let answered = secondMessages.filter { $0["role"] as? String == "tool" }
        XCTAssertEqual(answered.count, 1, "the model was not shown what the tool did")
        XCTAssertTrue((answered.first?["content"] as? String ?? "").contains("one"),
                      "the result never reached the model: \(answered.first?["content"] ?? "nothing")")
        // And the third carries both.
        let third = try Self.messages(try XCTUnwrap(provider.asks.last))
        XCTAssertEqual(third.filter { $0["role"] as? String == "tool" }.count, 2)

        // What the panel was told: the model's line, and the record.
        let sayings = events.compactMap { event -> String? in
            if case .saying(let said) = event { return said }
            return nil
        }
        XCTAssertEqual(sayings, ["First", "Second"])
        // The row the rail keeps, and the record the tool wrote.
        let steps = events.compactMap { event -> AIToolStep? in
            if case .did(let step) = event { return step }
            return nil
        }
        XCTAssertEqual(steps.map(\.audit), ["pretended: one", "pretended: two"], "one record for each call")
        XCTAssertEqual(steps.map(\.detail), [nil, nil], "and the receipt is not drawn on the row")
        XCTAssertEqual(steps.map(\.tool), ["pretend", "pretend"], "named by the tool that ran")
        XCTAssertEqual(steps.map(\.failed), [false, false])

        // What the conversation keeps: the answer, with the calls and results
        // that led to it, in order.
        XCTAssertEqual(added.count, 5)
        XCTAssertEqual(added.map { $0.role.rawValue }, ["assistant", "user", "assistant", "user", "assistant"])
        XCTAssertEqual(added[0].calls.count, 1)
        XCTAssertEqual(added[1].results.count, 1)
        XCTAssertEqual(added[4].text, "All done.")
    }

    /// A call that fails is a result, not an exception: the turn goes on and
    /// the model is told.
    /// No round limit, which is pi's design: its loop is
    /// `while (hasMoreToolCalls)` and counts nothing (`agent-loop.js`).
    /// Fifteen rounds is past the twelve this used to stop at, and the turn
    /// must still reach its answer.
    func testATurnIsNotCutOffAtATwelveRounds() async throws {
        var turns: [MockProvider.Turn] = (0..<15).map { round in
            .calls([("call_\(round)", "pretend", #"{"say": "Round \#(round)"}"#)])
        }
        turns.append(.words("The answer after fifteen rounds."))
        let provider = try MockProvider(turns: turns)
        server = provider
        AIProvider.mock = try XCTUnwrap(URL(string: "http://127.0.0.1:\(provider.port)"))

        let browser = Browser(record: WindowRecord())
        self.browser = browser
        let tab = browser.benchOpen(try XCTUnwrap(URL(string: "about:blank")))
        self.tab = tab

        let added = try await AIToolLoop.run(
            messages: [AIMessage(role: .user, text: "Keep going")],
            provider: .openAI, model: "test-model", system: "You are a test.",
            key: "sk-test-not-a-real-key", tools: tools([]),
            browser: browser, tab: tab, stopped: { false },
            check: { _, _ in .allowed },
            event: { _ in })

        XCTAssertEqual(provider.asks.count, 16, "a turn was cut off before the model answered")
        XCTAssertEqual(added.last?.text, "The answer after fifteen rounds.",
                       "the turn ended without an answer")
    }

    /// A page the assistant opens goes behind the one being read, never over
    /// it: Dia's `open_tabs` opens "new web pages in tabs in the current
    /// browser window", and the page you were reading is still there when it
    /// comes back. The tab's own id comes with the result, so the turn can go
    /// on reading it.
    func testOpeningAPageLeavesThePageInFrontWhereItWas() async throws {
        let browser = Browser(record: WindowRecord())
        self.browser = browser
        let reading = browser.benchOpen(try XCTUnwrap(URL(string: "about:blank")))
        self.tab = reading
        let before = browser.tabs.count
        // `benchOpen` does not put its tab in front, so what is in front is
        // read before the call rather than assumed.
        browser.select(reading)
        let inFront = browser.activeID

        let definition = try XCTUnwrap(AITool.named("navigate"))
        let context = AITool.Context(browser: browser, tab: reading, say: "Opening example.com")
        let result = await definition.run(AIToolArguments(text: #"{"url": "https://example.com/", "say": "Opening example.com"}"#),
                                          context)

        let opened = result.did
        XCTAssertEqual(browser.tabs.count, before + 1, "the page was not opened in a tab of its own")
        XCTAssertEqual(browser.activeID, inFront, "the page in front was replaced instead of left alone")
        XCTAssertTrue(reading.address?.absoluteString.contains("about:blank") == true,
                      "the page being read was navigated away")
        XCTAssertTrue(opened.contains("id is"), "the turn was not told which tab it may read: \(opened)")
    }

    /// A refusal is not the end of the turn: pi reads a blocked call as an
    /// ordinary error result and carries on, so the model answers from what it
    /// has. This is the case that used to leave a column of steps with nothing
    /// under them.
    func testARefusalStillEndsWithAnAnswer() async throws {
        let provider = try MockProvider(turns: [
            .calls([("call_1", "pretend", #"{"say": "First"}"#)]),
            .words("You did not allow that, so here is what I know."),
        ])
        server = provider
        AIProvider.mock = try XCTUnwrap(URL(string: "http://127.0.0.1:\(provider.port)"))

        let browser = Browser(record: WindowRecord())
        self.browser = browser
        let tab = browser.benchOpen(try XCTUnwrap(URL(string: "about:blank")))
        self.tab = tab

        let added = try await AIToolLoop.run(
            messages: [AIMessage(role: .user, text: "Do the thing")],
            provider: .openAI, model: "test-model", system: "You are a test.",
            key: "sk-test-not-a-real-key", tools: tools(["one"]),
            browser: browser, tab: tab, stopped: { false },
            check: { _, _ in .refused("Not this time.") },
            event: { _ in })

        XCTAssertEqual(added.last?.text, "You did not allow that, so here is what I know.",
                       "a refused turn ended on a tool result instead of an answer")
        // The last ask still carried tools; only the system prompt said no.
        XCTAssertEqual(provider.asks.count, 2)
    }

    func testAFailedCallIsAResultTheModelReads() async throws {
        let provider = try MockProvider(turns: [
            .calls([("call_1", "nowhere", "{}")]),
            .words("There's no such tool."),
        ])
        server = provider
        AIProvider.mock = try XCTUnwrap(URL(string: "http://127.0.0.1:\(provider.port)"))

        let browser = Browser(record: WindowRecord())
        self.browser = browser
        let tab = browser.benchOpen(try XCTUnwrap(URL(string: "about:blank")))
        self.tab = tab
        let said = tools(["one"])

        let added = try await AIToolLoop.run(
            messages: [AIMessage(role: .user, text: "Use the tool")],
            provider: .openAI, model: "test-model", system: "You are a test.",
            key: "sk-test-not-a-real-key", tools: said,
            browser: browser, tab: tab, stopped: { false },
            check: { _, _ in .allowed },
            event: { _ in })

        XCTAssertEqual(added.count, 3, "a failed call ended the turn instead of being a result")
        let result = try XCTUnwrap(added[1].results.first)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("nowhere"), result.content)
        XCTAssertEqual(added[2].text, "There's no such tool.")
    }

    /// A person who says no ends the batch: nothing else it asked for in the
    /// same message happens. The turn itself does not end — pi treats a
    /// blocked call as an ordinary error result, so the model is told and
    /// answers from what it has. Ending the turn on a refusal is what left a
    /// column of steps with no answer under them.
    func testARefusalEndsTheBatch() async throws {
        let provider = try MockProvider(turns: [
            .calls([("call_1", "pretend", #"{"say": "First"}"#),
                    ("call_2", "pretend", #"{"say": "Second"}"#)]),
            .words("Understood."),
        ])
        server = provider
        AIProvider.mock = try XCTUnwrap(URL(string: "http://127.0.0.1:\(provider.port)"))

        let browser = Browser(record: WindowRecord())
        self.browser = browser
        let tab = browser.benchOpen(try XCTUnwrap(URL(string: "about:blank")))
        self.tab = tab
        let offered = tools(["one", "two"])
        var ran = 0

        var refused = false
        let added = try await AIToolLoop.run(
            messages: [AIMessage(role: .user, text: "Use it twice")],
            provider: .openAI, model: "test-model", system: "You are a test.",
            key: "sk-test-not-a-real-key", tools: offered,
            browser: browser, tab: tab, stopped: { false },
            check: { _, _ in ran += 1; return ran > 1 ? .refused("no") : .allowed },
            event: { if case .refused = $0 { refused = true } })

        XCTAssertTrue(refused)
        // The first ran, the second did not, and the model was asked once
        // more — without tools — to answer about it.
        XCTAssertEqual(provider.asks.count, 2)
        // The first ran, the second is reported to the model as the refusal it
        // was: what a person says no to, the model is told about, and then the
        // turn is over.
        XCTAssertEqual(added[1].results.count, 2)
        XCTAssertFalse(added[1].results[0].isError, "the allowed call was reported as a failure")
        XCTAssertTrue(added[1].results[1].isError)
        XCTAssertTrue(added[1].results[1].content.contains("no"), added[1].results[1].content)
        XCTAssertEqual(added.count, 3, "the refusal ended the turn instead of being answered")
        XCTAssertEqual(added.last?.text, "Understood.")
    }
}

// MARK: - a provider on this Mac

/// A stand-in provider: the turns it is told to serve, in order, one per
/// request, and every request it was sent kept for the test to read.
private final class MockProvider {
    enum Turn {
        /// Tool calls, as (id, name, arguments).
        case calls([(String, String, String)])
        case words(String)
    }

    let port: UInt16
    private let socket: Int32
    private let source: DispatchSourceRead
    private var turns: [Turn]
    private let lock = NSLock()
    private(set) var asks: [[String: Any]] = []
    /// Why a request could not be read, when one could not be.
    private(set) var failed = ""
    private var stopped = false

    init(turns: [Turn]) throws {
        self.turns = turns
        let server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard server >= 0 else { throw Self.failure("socket") }
        socket = server
        var reuse: Int32 = 1
        _ = withUnsafePointer(to: &reuse) {
            setsockopt(server, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            bind(server, UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
        }
        guard bound == 0, listen(server, 8) == 0 else { throw Self.failure("bind/listen") }
        var bound_address = sockaddr_in()
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound_address) {
            getsockname(server, UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self), &size)
        }
        port = UInt16(bigEndian: bound_address.sin_port)
        source = DispatchSource.makeReadSource(fileDescriptor: server, queue: .global())
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
    }

    func stop() {
        lock.lock()
        let already = stopped
        stopped = true
        lock.unlock()
        guard !already else { return }
        source.cancel()
        close(socket)
    }

    private func accept() {
        let client = Darwin.accept(socket, nil, nil)
        guard client >= 0 else { return }
        // One request, one answer: a connection at a time is all the loop
        // makes, and reading it here keeps the order the model would see.
        DispatchQueue.global().async { [weak self] in
            defer { close(client) }
            guard let self else { return }
            guard let (head, body) = Self.read(client) else {
                self.failed = "the request never arrived"
                return
            }
            // A body that isn't a JSON object is this stand-in's own failure,
            // and says so rather than closing the connection in silence.
            guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
                self.failed = "head: " + head + " / body: " + String(decoding: body.prefix(400), as: UTF8.self)
                return
            }
            self.lock.lock()
            self.asks.append(json)
            let turn = self.turns.isEmpty ? Turn.words("") : self.turns.removeFirst()
            self.lock.unlock()
            self.serve(turn, to: client)
        }
    }

    /// A request, head and body. The head ends at its blank line; the body is
    /// read until it is a whole JSON object, rather than by its Content-Length
    /// — what a client says about its length is its own business.
    private static func read(_ client: Int32) -> (String, Data)? {
        var slow = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &slow, socklen_t(MemoryLayout<timeval>.size))
        var got = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while got.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = recv(client, &buffer, buffer.count, 0)
            guard n > 0 else { return nil }
            got.append(contentsOf: buffer[0..<n])
        }
        guard let split = got.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: got[..<split.lowerBound], as: UTF8.self)
        var body = Data(got[split.upperBound...])
        // Nothing to come: a request without a body is its own answer.
        if body.isEmpty, head.lowercased().contains("content-length: 0") { return (head, body) }
        while (try? JSONSerialization.jsonObject(with: body)) == nil {
            let n = recv(client, &buffer, buffer.count, 0)
            guard n > 0 else { return (head, body) }
            body.append(contentsOf: buffer[0..<n])
        }
        return (head, body)
    }

    private func serve(_ turn: Turn, to client: Int32) {
        var events: [String] = []
        switch turn {
        case .calls(let calls):
            for (index, call) in calls.enumerated() {
                // The name once, then the arguments a fragment at a time, as
                // OpenAI sends them.
                let opened: [String: Any] = ["choices": [["delta": ["tool_calls": [[
                    "index": index, "id": call.0,
                    "function": ["name": call.1, "arguments": ""]]]]]]]
                let arguments: [String: Any] = ["choices": [["delta": ["tool_calls": [[
                    "index": index, "function": ["arguments": call.2]]]]]]]
                events.append(Self.event(opened))
                events.append(Self.event(arguments))
            }
            events.append(Self.event(["choices": [["delta": [String: Any](), "finish_reason": "tool_calls"]]]))
        case .words(let words):
            if !words.isEmpty {
                events.append(Self.event(["choices": [["delta": ["content": words]]]]))
            }
            events.append(Self.event(["choices": [["delta": [String: Any](), "finish_reason": "stop"]]]))
        }
        var payload = Data(events.joined().utf8)
        payload.append(Data("data: [DONE]\n\n".utf8))
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        Self.send(Data(head.utf8), to: client)
        Self.send(payload, to: client)
    }

    /// Every byte, however many `send` calls it takes.
    private static func send(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { raw in
            guard var base = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                let wrote = Darwin.send(client, base, left, 0)
                guard wrote > 0 else { return }
                base += wrote
                left -= wrote
            }
        }
    }

    private static func event(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "data: \(data)\n\n"
    }

    private static func failure(_ what: String) -> NSError {
        NSError(domain: "MockProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: what])
    }
}
