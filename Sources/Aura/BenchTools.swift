import AppKit
import Foundation

// The assistant's hands, for the bench.
//
// AITool is the model's side of acting on a page; this is the same tools
// reached from the outside, one call at a time, so a probe can say "click 3"
// and read what the model would have read. It exists because the alternative
// is a real model in the loop: slow, expensive, and never the same twice.
//
// Nothing here is a second implementation. Every case builds an
// AIToolArguments the way a wire would and calls the tool's own `run`, so a
// test that passes says the tool works, not that this file does.

@MainActor
enum BenchTools {
    static func handle(_ request: [String: Any], browser: Browser, answer: @escaping ([String: Any]) -> Void) {
        guard Store.testing else { answer(["error": "ai tools only works on a --test run"]); return }
        let sub = request["sub"] as? String ?? "state"
        switch sub {
        case "on", "off":
            browser.prefs.aiTools = sub == "on"
            answer(["tools": browser.prefs.aiTools, "reveal": browser.prefs.aiToolsReveal])
        case "reveal":
            browser.prefs.aiToolsReveal = !browser.prefs.aiToolsReveal
            answer(["reveal": browser.prefs.aiToolsReveal])
        case "list":
            answer(["tools": AITool.all.map { tool in
                ["name": tool.name, "risk": "\(tool.risk)", "says": tool.says,
                 "required": tool.schema.required.sorted()] as [String: Any]
            }])
        case "classes":
            answer(rules(request))
        case "confirm":
            // What the person answers next, without a sheet standing in the
            // way: the questions are the slow part of a probe, not the tools.
            let said = (request["text"] as? String ?? "allow").lowercased()
            AIToolAsk.confirming = said == "always" ? .always : said == "refuse" ? .refuse : said == "off" ? nil : .allow
            answer(["confirming": said])
        case "answer":
            let said = (request["text"] as? String ?? "done").lowercased()
            AIToolAsk.answering = said == "stop" ? .stop : said == "cancel" ? .cancel : .done
            answer(["answering": said])
        case "snapshot":
            snapshot(request, browser: browser, answer: answer)
        default:
            call(sub, request, browser: browser, answer: answer)
        }
    }

    // MARK: - one call

    /// One tool, by name, with the arguments the request gives: `text` is the
    /// single string argument a call usually needs, `args` a whole object.
    private static func call(_ name: String, _ request: [String: Any], browser: Browser,
                             answer: @escaping ([String: Any]) -> Void) {
        guard let tool = AITool.named(name) else {
            answer(["error": "no tool called \(name)", "tools": AITool.all.map(\.name)]); return
        }
        guard let tab = find(request, in: browser) else {
            answer(["error": "no page to act on"]); return
        }
        var raw: [String: Any] = request["args"] as? [String: Any] ?? [:]
        // A whole arguments object wins over the shorthand: it is what a wire
        // would have sent, and a probe is usually standing in for one.
        if let text = request["text"] as? String { raw[pick(name, tool)] = text }
        if request["ref"] != nil { raw["ref"] = "\(request["ref"]!)" }
        if request["key"] != nil { raw["key"] = request["key"] }
        if request["url"] != nil { raw["url"] = request["url"] }
        if request["submit"] != nil { raw["submit"] = request["submit"] }
        if request["toolAction"] != nil { raw["action"] = request["toolAction"] }
        if request["value"] != nil { raw["value"] = request["value"] }
        // A probe that wants to see what a call without its line does says so;
        // otherwise the line is filled in the way a model would write one.
        if raw["say"] == nil, tool.says, (request["no-say"] as? Bool) != true { raw["say"] = "bench" }
        let arguments = AIToolArguments(raw)
        if let wrong = arguments.checked(against: tool.schema) {
            answer(["error": "arguments: \(wrong)", "tool": name]); return
        }
        let weigh = (request["weigh"] as? Bool) ?? false
        Task { @MainActor in
            var refusal = ""
            if weigh, case .refused(let why) = await AIToolRisk.weigh(tool: tool, arguments: arguments,
                                                                       in: browser, tab: tab) {
                refusal = why
            }
            if !refusal.isEmpty {
                answer(["tool": name, "refused": refusal, "error": refusal])
                return
            }
            let context = AITool.Context(browser: browser, tab: tab, say: raw["say"] as? String ?? "")
            let result = await tool.run(arguments, context)
            // A failed call is answered as the error `./bench` stops on, so a
            // probe reads it the way it reads any other refusal.
            var said: [String: Any] = ["tool": name, "content": result.content, "did": result.did]
            if result.isError { said["error"] = result.content }
            answer(said)
        }
    }

    /// Which argument a bare word goes into: the one the tool has that a
    /// single string would obviously be.
    private static func pick(_ name: String, _ tool: AITool.Definition) -> String {
        switch name {
        case "click": return "ref"
        case "scroll": return "ref"
        case "set_value": return "value"
        case "wait_for": return "text"
        case "tabs": return "action"
        default:
            for wanted in ["text", "url", "ref", "value"] where tool.schema.properties[wanted] != nil {
                return wanted
            }
            return "ref"
        }
    }

    // MARK: - the page as numbers

    /// The page as numbers, answered when the page answers. It is a round
    /// trip through WebKit, so the reply is a Task's, not this call's: a spin
    /// on the main loop would wait for a message that loop is what delivers.
    private static func snapshot(_ request: [String: Any], browser: Browser,
                                 answer: @escaping ([String: Any]) -> Void) {
        guard let tab = find(request, in: browser) else {
            answer(["error": "no page to snapshot"]); return
        }
        let scope = request["scope"].map { "\($0)" }
        let full = (request["full"] as? Bool) ?? false
        Task { @MainActor in
            guard let snap = await AIToolSnap.take(tab, scope: scope, full: full) else {
                answer(["error": "the page can't be read"]); return
            }
            answer(["text": snap.text, "count": snap.count])
        }
    }

    private static func rules(_ request: [String: Any]) -> [String: Any] {
        if (request["text"] as? String) == "forget" {
            AIToolRisk.forgetAll()
        }
        let cases: [(name: String, form: String, address: String)] = [
            ("Pay $40", "checkout", "https://shop.example/checkout"),
            ("Subscribe", "billing", "https://shop.example/"),
            ("Delete account", "", "https://social.example/settings"),
            ("Send", "Message", "https://mail.example/"),
            ("Allow camera", "", "https://video.example/"),
            ("Search", "q", "https://search.example/"),
            ("Log in", "", "https://bank.example/"),
        ]
        return ["remembered": AIToolRisk.remembered,
                "cases": cases.map { one in
                    let kind = AIToolRisk.classify(name: one.name, form: one.form,
                                                   address: URL(string: one.address))
                    return ["name": one.name, "site": one.address, "class": kind.map { "\($0)" } ?? "none"]
                }]
    }

    private static func find(_ request: [String: Any], in browser: Browser) -> Tab? {
        if let id = request["id"] as? String {
            return browser.tabs.first { $0.id.uuidString.lowercased().hasPrefix(id.lowercased()) }
        }
        return browser.active
    }
}
