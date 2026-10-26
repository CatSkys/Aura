import AppKit
import Foundation
import WebKit

// The tools the model can ask for, and what each one does when it does.
//
// A tool is five things and no more: a name, a description the model reads, a
// schema for its arguments, what happens when it is called, and how much
// damage the call can do (AIToolRisk). The name is the model's handle on it;
// the description is the only thing telling it when to reach for one, so it is
// written for the model rather than for us.
//
// Two sentences travel with every call, and they are not the same sentence:
//
//   · `say` is the model's, written into the call's arguments, and it is for
//     you — one line above the field saying what it is doing right now. It is
//     required, and a call without one is a failed call rather than one we
//     fill in for it.
//   · `did` is ours, written by the tool as it returns, and it is for the
//     model — what actually happened, including what changed on the page. It
//     goes into the tool's result, so it is also the record of what was done.
//
// Nothing here throws. Every way a tool can fail is a result the model reads
// and can correct itself from (AIToolLoop's eight steps), never an error
// thrown at the caller: a tool that throws teaches the model nothing.
//
// The refs a tool is given come from AIToolSnap, and go stale when the page's
// document does (Tab.didCommit). A stale ref is an error the model is told
// about by name, never a guess at what was meant.
//
// What each tool does to the page — a real mouse click, a field's own setter,
// a key handed to the view — is PageAct's, so the bench and the assistant are
// one act and not two that drift.

@MainActor
enum AITool {
    /// What a tool gives back: the record of the call, what else the model
    /// should read, and whether it worked.
    ///
    /// `did` is the record — verb, object, result — written truthfully by the
    /// tool and never by the model (which writes `say`, for you). It is the
    /// first line of `content`, so the model reads it first and can quote it
    /// when asked what it actually did; anything a call found rather than did
    /// follows it as `detail`.
    struct Result {
        var content: String
        var isError = false
        var did = ""

        static func ok(_ did: String, detail: String = "") -> Result {
            Result(content: detail.isEmpty ? did : did + "\n\n" + detail, did: did)
        }

        static func failed(_ why: String) -> Result {
            Result(content: why, isError: true)
        }
    }

    /// A tool's outcome, and whether the person was the one who stopped it.
    /// The loop is the only thing that reads `refused`: it ends the batch.
    struct Outcome {
        let result: Result
        var refused = false

        init(one result: Result, refused: Bool = false) {
            self.result = result
            self.refused = refused
        }
    }

    /// What a tool is given besides its arguments: the window it acts in, the
    /// tab it acts on, the model's line for you, and whether to stop.
    struct Context {
        let browser: Browser
        let tab: Tab
        let say: String
        var stopped: () -> Bool = { false }
    }

    // MARK: - the schema

    /// What a tool's arguments look like, in the little of JSON Schema the
    /// three providers all understand: an object with named properties, which
    /// of them are required, and each one's type.
    struct Schema {
        enum Kind: String {
            case string, number, boolean
        }

        struct Property {
            let kind: Kind
            let description: String
            /// The values it will take, when the list is short enough to be
            /// worth naming. Anything else is refused by validate.
            var choices: [String] = []

            init(_ kind: Kind, _ description: String, choices: [String] = []) {
                self.kind = kind
                self.description = description
                self.choices = choices
            }
        }

        var properties: [String: Property] = [:]
        var required: [String] = []
    }

    /// One tool, whole.
    struct Definition {
        let name: String
        let description: String
        let schema: Schema
        /// Whether the model must write a `say` for it: every tool that
        /// changes anything does, and one that only looks does not.
        let says: Bool
        let risk: AIToolRisk.Kind
        let run: (AIToolArguments, Context) async -> Result
    }

    /// The `say` field: one line for the person watching, which the model
    /// writes and we never write for it.
    static let sayProperty = Schema.Property(.string,
        "One short line for the person watching, in the language they are writing in: what this call is doing, in the present tense, at most 40 characters. No reasoning, and no claim that it worked.")

    /// A tool by its name, or nil for one we haven't got.
    static func named(_ name: String) -> Definition? { all.first { $0.name == name } }

    /// Every tool, in the order the model is given them.
    static var all: [Definition] { observations + navigation + actions + interactions }

    // MARK: - looking

    private static var observations: [Definition] {
        [
            Definition(
                name: "snapshot",
                description: "A numbered list of everything on the page a person could click, type into or read as a control — buttons, links, fields, boxes — each with the number the other tools take. Call it before acting, and again after the page has changed.",
                schema: Schema(properties: [
                    "scope": .init(.string, "Only what is inside this element, by its number from an earlier snapshot."),
                    "full": .init(.boolean, "Every element in the document, not only those near the screen."),
                ]),
                says: false, risk: .reading,
                run: { arguments, context in await snapshot(arguments, context) }
            ),
            Definition(
                name: "read",
                description: "The words of the page as a person reading it would see them: its article, or the whole page when there is no article.",
                schema: Schema(properties: [:]),
                says: false, risk: .reading,
                run: { _, context in await read(context) }
            ),
            Definition(
                name: "tabs",
                description: "Your tabs: list them, open one on an address, bring one to the front, or close one.",
                schema: Schema(
                    properties: [
                        "action": .init(.string, "What to do with the tabs.", choices: ["list", "open", "select", "close"]),
                        "url": .init(.string, "For open: the http or https address to open."),
                        "id": .init(.string, "For select and close: the tab's id, as the list gives it."),
                        "say": sayProperty,
                    ],
                    required: ["action", "say"]
                ),
                says: true, risk: .acting,
                run: { arguments, context in await tabs(arguments, context) }
            ),
            Definition(
                name: "screenshot",
                description: "A picture of the page as it is on screen, for a model that can look at one.",
                schema: Schema(properties: [:]),
                says: false, risk: .reading,
                run: { _, context in await screenshot(context) }
            ),
        ]
    }

    // MARK: - going places

    private static var navigation: [Definition] {
        [
            Definition(
                name: "navigate",
                description: "Open an address in this tab. Only http and https: an address with any other scheme is refused.",
                schema: Schema(
                    properties: [
                        "url": .init(.string, "The whole address, beginning https:// or http://. Take it from the page or from what you were asked — never make one up."),
                        "say": sayProperty,
                    ],
                    required: ["url", "say"]
                ),
                says: true, risk: .going,
                run: { arguments, context in await navigate(arguments, context) }
            ),
            Definition(
                name: "back",
                description: "Back to the page before this one.",
                schema: Schema(properties: ["say": sayProperty], required: ["say"]),
                says: true, risk: .going,
                run: { _, context in history(back: true, context) }
            ),
            Definition(
                name: "forward",
                description: "Forward to the page this one came back from.",
                schema: Schema(properties: ["say": sayProperty], required: ["say"]),
                says: true, risk: .going,
                run: { _, context in history(back: false, context) }
            ),
            Definition(
                name: "reload",
                description: "Load the page again.",
                schema: Schema(properties: ["say": sayProperty], required: ["say"]),
                says: true, risk: .going,
                run: { _, context in reload(context) }
            ),
        ]
    }

    // MARK: - acting

    private static var actions: [Definition] {
        [
            Definition(
                name: "click",
                description: "Click an element, as a hand would: a real press and release, which sign-in boxes and password managers accept.",
                schema: Schema(
                    properties: [
                        "ref": .init(.string, "The element's number from a snapshot."),
                        "say": sayProperty,
                    ],
                    required: ["ref", "say"]
                ),
                says: true, risk: .acting,
                run: { arguments, context in await click(arguments, context) }
            ),
            Definition(
                name: "set_value",
                description: "Type into a field, as a paste would: the field's own value is set and the events a change sends go with it, so a page built with React or Vue notices.",
                schema: Schema(
                    properties: [
                        "ref": .init(.string, "The field's number from a snapshot."),
                        "value": .init(.string, "What to put in it."),
                        "submit": .init(.boolean, "Send the form around it afterwards."),
                        "say": sayProperty,
                    ],
                    required: ["ref", "value", "say"]
                ),
                says: true, risk: .acting,
                run: { arguments, context in await setValue(arguments, context) }
            ),
            Definition(
                name: "press",
                description: "Press one key on the page, as a keyboard would: Enter, Tab, Escape, the arrows.",
                schema: Schema(
                    properties: [
                        "key": .init(.string, "The key's name: Enter, Tab, Escape, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, PageUp, PageDown, Home, End, Space, Backspace, Delete."),
                        "ref": .init(.string, "Press it in this element, after putting the focus there."),
                        "say": sayProperty,
                    ],
                    required: ["key", "say"]
                ),
                says: true, risk: .acting,
                run: { arguments, context in await press(arguments, context) }
            ),
            Definition(
                name: "scroll",
                description: "Scroll the page, or bring an element into view.",
                schema: Schema(
                    properties: [
                        "direction": .init(.string, "Which way to scroll.", choices: ["up", "down"]),
                        "pages": .init(.number, "How many screens, one by default."),
                        "ref": .init(.string, "Scroll this element into view instead."),
                        "say": sayProperty,
                    ],
                    required: ["say"]
                ),
                says: true, risk: .acting,
                run: { arguments, context in await scroll(arguments, context) }
            ),
        ]
    }

    // MARK: - talking to you

    private static var interactions: [Definition] {
        [
            Definition(
                name: "wait_for",
                description: "Wait until an element appears, or the address changes, or the page stops loading. Polled from outside the page, so a page that blocks timers still settles.",
                schema: Schema(properties: [
                    "ref": .init(.string, "Wait for this element to be on the page."),
                    "text": .init(.string, "Wait for this text to appear."),
                    "state": .init(.string, "What to wait for.", choices: ["loaded", "navigation"]),
                    "timeoutMs": .init(.number, "How long to wait, in milliseconds. Ten seconds by default, one minute at most."),
                ]),
                says: false, risk: .reading,
                run: { arguments, context in await waitFor(arguments, context) }
            ),
            Definition(
                name: "ask_user",
                description: "Stop and ask the person, in a card over the page. For a sign-in, a code sent to their phone, a password, a payment, or anything only they can decide. Never fill any of that in for them.",
                schema: Schema(
                    properties: [
                        "reason": .init(.string, "What you need from them, in one sentence."),
                        "title": .init(.string, "A few words saying what this is about, in the language they are writing in."),
                    ],
                    required: ["reason", "title"]
                ),
                says: false, risk: .reading,
                run: { arguments, context in await askUser(arguments, context) }
            ),
        ]
    }

    // MARK: - looking, done

    private static func snapshot(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        let scope = arguments.string("scope")
        let full = arguments.bool("full")
        // A scope the page never gave is a made-up number: the whole page is a
        // better answer than nothing, and the snapshot itself says so.
        if let scope, Int(scope) == nil { return .failed("scope must be an element's number from a snapshot.") }
        guard let snap = await AIToolSnap.take(context.tab, scope: scope, full: full) else {
            return .failed("This page can't be read right now: it has no document, or it is still on its way.")
        }
        return .ok("Took a snapshot of the page: \(snap.count) element\(snap.count == 1 ? "" : "s").", detail: snap.text)
    }

    private static func read(_ context: Context) async -> Result {
        guard let read = await AIPage.read(context.tab) else {
            return .failed("There's nothing readable on this page.")
        }
        let head = "\(read.title)\n\(read.url?.absoluteString ?? "")\n\n"
        return .ok("Read the page “\(read.title)”.", detail: head + read.text)
    }

    private static func tabs(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        switch arguments.string("action") ?? "" {
        case "list":
            let lines = context.browser.tabs.map { tab in
                let mark = tab.id == context.tab.id ? " (this one)" : ""
                let named = tab.title.isEmpty ? (tab.pageAddress?.host() ?? "untitled") : tab.title
                return "- \(Short.id(tab)): \(named) — \(tab.pageAddress?.absoluteString ?? "")\(mark)"
            }
            return .ok("Listed \(context.browser.tabs.count) tab\(context.browser.tabs.count == 1 ? "" : "s").",
                           detail: lines.joined(separator: "\n"))
        case "open":
            let text = arguments.string("url") ?? ""
            guard let url = AIToolRisk.address(text) else {
                return .failed("Only http and https addresses can be opened. “\(text)” is not one.")
            }
            context.browser.open(url, foreground: false)
            return .ok("Opened \(url.absoluteString) in a new tab behind this one.")
        case "select":
            guard let tab = match(arguments.string("id"), in: context) else {
                return .failed("There's no tab with that id. List them again with tabs list.")
            }
            context.browser.select(tab)
            return .ok("Brought “\(tab.title)” to the front.")
        case "close":
            guard let tab = match(arguments.string("id"), in: context) else {
                return .failed("There's no tab with that id. List them again with tabs list.")
            }
            guard tab.id != context.tab.id else {
                return .failed("That's the tab this conversation is acting in. Leave it open, or ask the person which one to close.")
            }
            let name = tab.title
            context.browser.close(tab)
            return .ok("Closed “\(name)”.")
        default:
            return .failed("action must be one of list, open, select, close.")
        }
    }

    private static func match(_ id: String?, in context: Context) -> Tab? {
        guard let id, !id.isEmpty else { return nil }
        return context.browser.tabs.first { Short.matches($0, id) }
    }

    private static func screenshot(_ context: Context) async -> Result {
        guard let shot = await AIPage.shot(context.tab), !shot.isEmpty else {
            return .failed("This page can't be pictured.")
        }
        // A picture can't ride in a tool result on any of the three wires, so
        // it leaves here and the loop carries it on the next turn.
        AIToolLoop.keep(shot)
        return .ok("Took a picture of the page, as it is now.")
    }

    // MARK: - going places, done

    private static func navigate(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        let text = (arguments.string("url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AIToolRisk.address(text) else {
            return .failed("Only http and https addresses can be opened. “\(text)” is not one.")
        }
        context.tab.go(to: url)
        let landed = await settle(context.tab, upTo: 15)
        return .ok("Opened \(landed).")
    }

    private static func history(back: Bool, _ context: Context) -> Result {
        let can = back ? context.tab.canGoBack : context.tab.canGoForward
        guard can else {
            return .failed(back ? "There's no page before this one." : "There's no page after this one.")
        }
        if back { context.tab.web.goBack() } else { context.tab.web.goForward() }
        return .ok(back ? "Went back." : "Went forward.")
    }

    private static func reload(_ context: Context) -> Result {
        context.tab.web.reload()
        return .ok("Loaded the page again.")
    }

    // MARK: - acting, done

    private static func click(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        let id = arguments.string("ref") ?? ""
        guard let element = await AIToolSnap.element(id, in: context.tab) else {
            return .failed(missing(id, context))
        }
        // What is about to be pressed, shown on the page before the mouse
        // moves — and never in the way of the click itself.
        AIToolReveal.flash(element, in: context.tab)
        let before = context.browser.tabs.count
        guard let point = await AIToolSnap.point(of: element, in: context.tab) else {
            return .failed("\(element.described) is off the screen and couldn't be scrolled to.")
        }
        guard let web = context.tab.built else { return .failed("This page has no view to click in.") }
        guard PageAct.press(web.webKit, at: point) else {
            return .failed("The page isn't in a window, so the click had nowhere to land.")
        }
        // What a person's own click would say afterwards, when it is worth
        // saying: a new tab is the thing the model most needs to know.
        let opened = context.browser.tabs.count > before
        let did = "Clicked \(element.described)" + (opened ? " (" + Localized("opened in a new tab") + ")" : "") + "."
        let landed = await settle(context.tab, upTo: 8)
        return .ok(did, detail: "The page is now \(landed).")
    }

    private static func setValue(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        let id = arguments.string("ref") ?? ""
        guard let element = await AIToolSnap.element(id, in: context.tab) else {
            return .failed(missing(id, context))
        }
        guard element.takesText else {
            return .failed("\(element.described) isn't something you can type into.")
        }
        let value = arguments.string("value") ?? ""
        AIToolReveal.flash(element, in: context.tab)
        guard await AIToolSnap.fill(element, with: value, in: context.tab) else {
            return .failed("The value couldn't be put into \(element.described).")
        }
        // A password is never the record's business: the field's name, and no
        // more of it.
        let did = element.isSecret
            ? "Filled in \(element.described)."
            : "Filled in \(element.described) with \(Short.tail(value))."
        if arguments.bool("submit") {
            guard await AIToolSnap.submit(element, in: context.tab) != nil else {
                return .ok(did, detail: "There's no form around it to send.")
            }
            let landed = await settle(context.tab, upTo: 8)
            return .ok(did + " Sent the form around it.", detail: "The page is now \(landed).")
        }
        return .ok(did)
    }

    private static func press(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        guard let key = arguments.string("key").flatMap(PageAct.Key.init(name:)) else {
            return .failed("That key isn't one this can press. Try Enter, Tab, Escape, the arrows, Home, End, Page Up, Page Down, Space or Backspace.")
        }
        if let id = arguments.string("ref") {
            guard let element = await AIToolSnap.element(id, in: context.tab) else {
                return .failed(missing(id, context))
            }
            AIToolReveal.flash(element, in: context.tab)
            await AIToolSnap.focus(element, in: context.tab)
        }
        guard let web = context.tab.built else { return .failed("This page has no view to press a key in.") }
        guard PageAct.press(key, in: web.webKit) else {
            return .failed("The page isn't in a window, so the key had nowhere to go.")
        }
        if key.submits {
            let landed = await settle(context.tab, upTo: 5)
            return .ok("Pressed \(key.name). The page is now \(landed).")
        }
        return .ok("Pressed \(key.name).")
    }

    private static func scroll(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        if let id = arguments.string("ref") {
            guard let element = await AIToolSnap.element(id, in: context.tab) else {
                return .failed(missing(id, context))
            }
            await AIToolSnap.intoView(element, in: context.tab)
            return .ok("Scrolled \(element.described) into view.")
        }
        let up = arguments.string("direction") == "up"
        let pages = min(max(arguments.number("pages") ?? 1, 0.25), 20)
        guard let web = context.tab.built else { return .failed("This page has no view to scroll.") }
        let amount = up ? -pages : pages
        web.webKit.evaluateJavaScript("window.scrollBy(0, \(amount) * window.innerHeight); true",
                                      in: nil, in: Web.world) { _ in }
        return .ok("Scrolled \(Short.number(pages)) screen\(pages == 1 ? "" : "s") \(up ? "up" : "down").")
    }

    // MARK: - waiting and asking

    private static func waitFor(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        let limit = min(max(arguments.number("timeoutMs") ?? 10_000, 250), 60_000) / 1000
        let state = arguments.string("state")
        let ref = arguments.string("ref")
        let text = arguments.string("text")
        guard state != nil || ref != nil || text != nil else {
            return .failed("wait_for needs one of ref, text or state to wait for.")
        }
        let start = Date()
        while Date().timeIntervalSince(start) < limit {
            if context.stopped() { return .failed("The person stopped this.") }
            switch state {
            case "loaded":
                if !context.tab.loading { return .ok("Waited, and the page has stopped loading.") }
            case "navigation":
                // A second's grace: the address that was there before the
                // click hasn't gone anywhere yet.
                if !context.tab.loading, Date().timeIntervalSince(start) > 1 {
                    let now = context.tab.pageAddress?.absoluteString ?? ""
                    return .ok("Waited, and the address is now \(now).")
                }
            default:
                if let ref {
                    if await AIToolSnap.element(ref, in: context.tab) != nil {
                        return .ok("Waited, and element \(ref) is on the page.")
                    }
                    if AIToolSnap.stale(ref, in: context.tab) {
                        return .failed("ref \(ref) has gone: the page has changed. Take a new snapshot.")
                    }
                } else if let text, let found = await AIToolSnap.contains(text, in: context.tab) {
                    return .ok("Waited, and the page now has “\(found)”.")
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let what = state == "loaded" ? "stop loading"
            : state == "navigation" ? "change address"
            : ref.map { "show element \($0)" } ?? text.map { "show “\($0)”" } ?? "change"
        // Rounded up: a wait refused at 0.6 seconds is not "0 seconds".
        return .failed("Waited \(Int(limit.rounded(.up))) seconds and the page didn't \(what).")
    }

    private static func askUser(_ arguments: AIToolArguments, _ context: Context) async -> Result {
        let title = arguments.string("title") ?? ""
        let reason = arguments.string("reason") ?? ""
        guard let asking = context.browser.chat?.asking else {
            return .ok(Localized("Asked you."), detail: Localized("No conversation to ask in."))
        }
        switch await asking.ask(title: title, reason: reason) {
        case .done:
            return .ok("Asked the person “\(title)”, and they have answered: they are ready for you to go on. Take a new snapshot before acting.")
        case .stop:
            return .failed("The person stopped here.")
        case .cancel:
            return .failed("The person closed the question without answering. Nothing was done.")
        }
    }

    // MARK: - plumbing

    /// What to tell the model about a number it used and the page hasn't got:
    /// one it was given and lost, or one it made up.
    private static func missing(_ id: String, _ context: Context) -> String {
        AIToolSnap.stale(id, in: context.tab)
            ? "ref \(id) has gone: the page has changed since that snapshot. Take a new snapshot."
            : "There's no element \(id) on this page. Take a snapshot."
    }

    /// Where the page ended up, once it has stopped loading, or where it had
    /// got to when the time was up: what a `did` says happened.
    private static func settle(_ tab: Tab, upTo seconds: Double) async -> String {
        let until = Date().addingTimeInterval(seconds)
        while tab.loading, Date() < until {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return tab.pageAddress?.absoluteString ?? "about:blank"
    }
}

// MARK: - names for things

/// A tab or a value, short enough to say in a `did` and long enough to be
/// sure which one it was.
enum Short {
    static func id(_ tab: Tab) -> String { String(tab.id.uuidString.prefix(8)).lowercased() }

    static func matches(_ tab: Tab, _ id: String) -> Bool {
        tab.id.uuidString.lowercased().hasPrefix(id.lowercased())
    }

    /// A value as a record may repeat it: short, and never so long that the
    /// record becomes the page.
    static func tail(_ value: String) -> String {
        value.count <= 60 ? value : String(value.prefix(57)) + "…"
    }

    /// The English of the same, for a result the model reads.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
