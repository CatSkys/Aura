import Foundation
import OSLog

// The AI add-on's requests, and nothing else's: a session of its own, with
// no cookies, no cache and nothing remembered, that speaks only to the
// provider chosen — https, or plain http to this Mac alone — and follows no
// redirect, so a key never goes anywhere but the host it was kept for.
// Aura lets pages load from anywhere (NSAllowsArbitraryLoads, as a browser
// must), so none of this is left to App Transport Security.
//
// Three ways of writing a request cover every provider: OpenAI's chat
// completions (OpenAI, OpenRouter, Ollama, LM Studio), Anthropic's messages
// and Gemini's generateContent. Each answer comes back a piece at a time, as
// server-sent events, and is handed on as text.
//
// Nothing of a request is logged: not the page, the question, the answer,
// the address with its query or a header. An error says what the provider
// said, with any key it echoed taken out.

struct AIMessage: Equatable {
    enum Role: String { case user, assistant }
    let role: Role
    let text: String
    /// Pictures that go with it, as JPEG: a page's own look, when a model
    /// that can see was asked (see AIPage.shot). Only ever on the question
    /// being asked — the history keeps the words.
    var images: [Data] = []
    /// The tools this turn asked for (see AIToolLoop): only ever on an
    /// assistant message, and only once the assistant has finished asking —
    /// a half-streamed call is not a call.
    var calls: [AIToolWires.Call] = []
    /// What came back from those calls: only ever on a user message, and
    /// paired with `calls` by id.
    var results: [AIToolResult] = []
}

/// One tool's answer, as it goes back to the model: which call it answers,
/// what the model reads, and whether it worked (see AIToolLoop's rules on
/// failing without throwing).
struct AIToolResult: Equatable {
    let id: String
    let name: String
    let content: String
    let isError: Bool
}

enum AIError: LocalizedError, Equatable {
    case noKey
    case refusedHost
    case http(Int, String)
    case unreadable
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return Localized("No key is kept for this provider.")
        case .refusedHost: return Localized("That address isn't the provider's.")
        case .http(let status, let said):
            return said.isEmpty ? Localized("The provider answered \(status).") : "\(said) (\(status))"
        case .unreadable: return Localized("The provider's answer couldn't be read.")
        case .unreachable(let why): return why
        }
    }
}

final class AIClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = AIClient()

    private static let log = Logger(subsystem: "com.catskys.aura", category: "AI")

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Where a provider's requests may go: its own host, over https, or
    /// this Mac over plain http for the apps that run on it.
    static func allowed(_ url: URL, for provider: AIProvider) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(),
              url.user == nil, url.password == nil
        else { return false }
        let loopback = host == "127.0.0.1" || host == "::1" || host == "localhost"
        if provider.isLocal || (Store.testing && AIProvider.mock != nil) {
            return (scheme == "http" || scheme == "https") && loopback && host == provider.host
        }
        return scheme == "https" && host == provider.host
    }

    /// A key is sent only by these, and only to the provider's own host.
    /// A redirect — to the same host or not — is refused rather than
    /// followed with the key still on the request.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    // MARK: - asking

    /// The answer to `messages`, a piece at a time. `system` says what the
    /// model is for and how to treat the page (see AIPage.system).
    ///
    /// `tools` are the tools it may ask for (see AITool). `on` is told each
    /// call as it is complete, and is what the caller's loop uses; the pieces
    /// are the words, which the panel writes as they come.
    func stream(_ provider: AIProvider, model: String, system: String, messages: [AIMessage],
                key: String?, tools: [AITool.Definition] = [],
                on heard: (@MainActor (AIToolWires.Call) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.request(provider, model: model, system: system, messages: messages,
                                                   key: key, tools: tools)
                    let (bytes, response) = try await session.bytes(for: request, delegate: self)
                    guard let http = response as? HTTPURLResponse else { throw AIError.unreadable }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 4096 { break }
                        }
                        throw AIError.http(http.statusCode, Self.said(body, hiding: key))
                    }
                    var event = ""
                    var reader = AIToolWires.Reader(provider.wire)
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if data == "[DONE]" { break }
                        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { continue }
                        if let failure = Self.failure(json, event: event, hiding: key) { throw failure }
                        if let piece = Self.piece(provider.wire, json), !piece.isEmpty { continuation.yield(piece) }
                        for call in reader.read(json) { await heard?(call) }
                    }
                    // What a wire sends in pieces is whole only now.
                    for call in reader.finished() { await heard?(call) }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch let error as URLError {
                    // The address stays out of it: only what went wrong.
                    continuation.finish(throwing: AIError.unreachable(Self.reason(error, provider)))
                } catch {
                    continuation.finish(throwing: AIError.unreadable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The request as the provider wants it, with the key in a header — never
    /// in the address, which ends up in errors and logs — and only once the
    /// address is known to be the provider's own.
    static func request(_ provider: AIProvider, model: String, system: String, messages: [AIMessage],
                        key: String?, tools: [AITool.Definition] = []) throws -> URLRequest {
        let url: URL
        var body: [String: Any]
        // A tool's calls and their results are written differently by each
        // wire, so a message is flattened into the turns each wants: a turn
        // the model took (its words and its calls), then the answers to those
        // calls as the messages or blocks that wire gives them.
        let turns = Self.turns(provider.wire, messages)
        switch provider.wire {
        case .openAI:
            url = provider.base.appendingPathComponent("chat/completions")
            body = [
                "model": model, "stream": true,
                "messages": [["role": "system", "content": system]] + turns,
            ]
            if let declared = AIToolWires.openAI(tools) {
                body["tools"] = declared
                body["tool_choice"] = "auto"
            }
            // Only providers that keep nothing of the request.
            if provider == .openRouter { body["provider"] = ["zdr": true] }
            // A limit on the answer, for every one: OpenAI's own models take
            // it under its newer name.
            body[provider == .openAI ? "max_completion_tokens" : "max_tokens"] = 2048
        case .anthropic:
            url = provider.base.appendingPathComponent("messages")
            body = [
                "model": model, "stream": true, "max_tokens": 2048, "system": system,
                "messages": turns,
            ]
            if let declared = AIToolWires.anthropic(tools) {
                body["tools"] = declared
                body["tool_choice"] = ["type": "auto"]
            }
        case .gemini:
            // The model's name is part of the path; nothing of the key is.
            let name = model.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._"))) ?? ""
            var parts = URLComponents(url: provider.base.appendingPathComponent("models/\(name):streamGenerateContent"), resolvingAgainstBaseURL: false)
            parts?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            guard let made = parts?.url else { throw AIError.refusedHost }
            url = made
            body = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": turns,
                "generationConfig": ["maxOutputTokens": 2048],
            ]
            if let declared = AIToolWires.gemini(tools) { body["tools"] = declared }
        }
        guard allowed(url, for: provider) else { throw AIError.refusedHost }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !provider.isLocal {
            guard let key, !key.isEmpty else { throw AIError.noKey }
            switch provider.wire {
            case .anthropic:
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            case .gemini:
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            case .openAI:
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The history as turns, for one wire: a message with pictures or with
    /// calls is written out as that wire's own shape, and a message with
    /// nothing in it but results becomes the block or message that wire
    /// answers a call in.
    private static func turns(_ wire: AIProvider.Wire, _ messages: [AIMessage]) -> [Any] {
        var turns: [Any] = []
        for message in messages {
            if message.role == .assistant, !message.calls.isEmpty {
                let said = AIToolWires.assistant(wire, text: message.text, calls: message.calls)
                turns.append(said)
                continue
            }
            if message.role == .user, !message.results.isEmpty {
                let answers = message.results.map { result in
                    AIToolWires.result(wire, id: result.id, name: result.name,
                                       content: result.content, isError: result.isError)
                }
                if AIToolWires.resultsAreTheirOwnMessage(wire) {
                    turns += answers
                } else {
                    // Anthropic: the results are blocks of a user's turn, and
                    // any words with them come first.
                    var blocks: [[String: Any]] = []
                    if !message.text.isEmpty { blocks.append(["type": "text", "text": message.text]) }
                    turns.append(["role": "user", "content": blocks + answers.compactMap { $0 as? [String: Any] }])
                }
                continue
            }
            switch wire {
            case .openAI:
                turns.append(["role": message.role.rawValue, "content": openAIContent(message)])
            case .anthropic:
                turns.append(["role": message.role.rawValue, "content": anthropicContent(message)])
            case .gemini:
                turns.append(["role": message.role == .user ? "user" : "model", "parts": geminiParts(message)])
            }
        }
        return turns
    }

    /// A message as each way of writing wants it: the words alone, or the
    /// words and the pictures with them. A message with no pictures stays a
    /// plain string, which every server understands.
    private static func openAIContent(_ message: AIMessage) -> Any {
        guard !message.images.isEmpty else { return message.text }
        var parts: [[String: Any]] = [["type": "text", "text": message.text]]
        for image in message.images {
            parts.append(["type": "image_url",
                          "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]])
        }
        return parts
    }

    private static func anthropicContent(_ message: AIMessage) -> Any {
        guard !message.images.isEmpty else { return message.text }
        var parts: [[String: Any]] = [["type": "text", "text": message.text]]
        for image in message.images {
            parts.append(["type": "image",
                          "source": ["type": "base64", "media_type": "image/jpeg",
                                     "data": image.base64EncodedString()]])
        }
        return parts
    }

    private static func geminiParts(_ message: AIMessage) -> [[String: Any]] {
        var parts: [[String: Any]] = [["text": message.text]]
        for image in message.images {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": image.base64EncodedString()]])
        }
        return parts
    }

    /// OpenRouter's one-time code, and the flow's verifier, for a key of
    /// the account's own.
    func exchange(code: String, verifier: String) async throws -> String {
        let url = AIProvider.openRouter.base.appendingPathComponent("auth/keys")
        guard Self.allowed(url, for: .openRouter) else { throw AIError.refusedHost }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": verifier, "code_challenge_method": "S256"])
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: self)
        } catch let error as URLError {
            throw AIError.unreachable(Self.reason(error, .openRouter))
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.unreadable }
        guard (200..<300).contains(http.statusCode) else { throw AIError.http(http.statusCode, Self.said(data, hiding: nil)) }
        guard let key = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["key"] as? String,
              !key.isEmpty, key.count < 400
        else { throw AIError.unreadable }
        return key
    }

    /// The models a provider offers, asked only when Settings shows them: an
    /// app on this Mac, or the API of your own. Ollama's "cloud" models, which
    /// it runs on ollama.com, are left out: nothing chosen there leaves this
    /// Mac.
    @MainActor
    func models(_ provider: AIProvider) async -> [String] {
        guard provider.isLocal || provider == .custom else { return [] }
        let url = provider == .ollama
            ? provider.base.deletingLastPathComponent().appendingPathComponent("api/tags")
            : provider.base.appendingPathComponent("models")
        guard Self.allowed(url, for: provider) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = provider.isLocal ? 2 : 8
        // Your own API is asked with its key, the way it is asked anything.
        if !provider.isLocal, let key = AIKeys.key(for: provider), !key.isEmpty {
            switch provider.wire {
            case .anthropic:
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            case .gemini:
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            case .openAI:
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }
        guard let (data, response) = try? await session.data(for: request, delegate: self),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        if provider == .ollama {
            return (json["models"] as? [[String: Any]] ?? []).compactMap { model in
                guard let name = model["name"] as? String, model["remote_host"] == nil, model["remote_model"] == nil,
                      !name.hasSuffix("-cloud"), !name.contains(":cloud"), !name.contains("-cloud:")
                else { return nil }
                return name
            }
        }
        return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    // MARK: - reading

    /// The text in one event, for each way of writing.
    static func piece(_ wire: AIProvider.Wire, _ json: [String: Any]) -> String? {
        switch wire {
        case .openAI:
            let choice = (json["choices"] as? [[String: Any]])?.first
            return (choice?["delta"] as? [String: Any])?["content"] as? String
        case .anthropic:
            guard json["type"] as? String == "content_block_delta",
                  let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta"
            else { return nil }
            return delta["text"] as? String
        case .gemini:
            let candidate = (json["candidates"] as? [[String: Any]])?.first
            let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            // A model that thinks marks those parts; only the answer is shown.
            return parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        }
    }

    /// An error sent inside the stream, as Anthropic and OpenRouter do.
    static func failure(_ json: [String: Any], event: String, hiding key: String?) -> AIError? {
        guard event == "error" || json["type"] as? String == "error" || json["error"] != nil else { return nil }
        let error = json["error"] as? [String: Any]
        let said = (error?["message"] as? String) ?? (json["error"] as? String) ?? ""
        return .http((error?["code"] as? Int) ?? 500, scrub(String(said.prefix(300)), hiding: key))
    }

    /// What an error's body says, in a line, with any key taken out: some
    /// providers quote part of a refused key back.
    static func said(_ body: Data, hiding key: String?) -> String {
        let json = try? JSONSerialization.jsonObject(with: body)
        var message = ""
        if let object = json as? [String: Any] {
            let error = object["error"]
            message = (error as? [String: Any])?["message"] as? String ?? (error as? String) ?? (object["message"] as? String) ?? ""
        } else if let list = json as? [[String: Any]], let first = list.first?["error"] as? [String: Any] {
            message = first["message"] as? String ?? ""
        }
        return scrub(String(message.prefix(300)), hiding: key)
    }

    /// Any key out of a text: the one sent, and anything shaped like one.
    static func scrub(_ text: String, hiding key: String?) -> String {
        var text = text
        if let key, key.count >= 8 {
            text = text.replacingOccurrences(of: key, with: "••••")
            // A quoted part of it, as "sk-abc…wxyz" is.
            text = text.replacingOccurrences(of: String(key.prefix(8)), with: "••••")
            text = text.replacingOccurrences(of: String(key.suffix(4)), with: "••••")
        }
        let shapes = [#"sk-[A-Za-z0-9_\-*.]{6,}"#, #"AIza[A-Za-z0-9_\-]{10,}"#, #"AQ\.[A-Za-z0-9_\-]{10,}"#, #"gsk_[A-Za-z0-9]{10,}"#]
        for shape in shapes {
            text = text.replacingOccurrences(of: shape, with: "••••", options: .regularExpression)
        }
        return text
    }

    private static func reason(_ error: URLError, _ provider: AIProvider) -> String {
        switch error.code {
        case .cannotConnectToHost where provider.isLocal: return Localized("\(provider.name) isn't running on this Mac.")
        case .notConnectedToInternet: return Localized("This Mac is offline.")
        case .timedOut: return Localized("\(provider.name) took too long to answer.")
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .secureConnectionFailed:
            return Localized("The connection to \(provider.name) isn't secure.")
        default: return Localized("\(provider.name) couldn't be reached.")
        }
    }
}
