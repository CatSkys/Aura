import SwiftUI

// The conversation: one thread, whether it is beside a page or on a page of
// its own. Dia's assistant is this — the column beside the page while you
// read (SidePanel.swift's `.ai`), the same conversation filling a page of its
// own when you want the lot (`search://chat`, ChatsPanel.swift), and the list
// of them all in Chats.swift. It belongs to the window rather than to a page,
// so it is carried from tab to tab, and the page you are on goes with each
// question when it can be read.
//
// What it can do is one machinery — AIPage's reading, AIClient's or
// AIEngine's stream — so a summary of the page and a question about it are
// the same request written differently: Summarize Page is this conversation's
// first thing said. That is the whole of the page assistant that used to live
// in a card of its own (AIAssist), merged here so there is one conversation
// per window and not three things that each pretend to be one.
//
// A private tab's text never leaves this Mac: it is attached only for a
// provider that runs here.

@MainActor
final class Chat: ObservableObject, Identifiable {
    /// One thing said, by you or to you. Dia's grammar: yours in a bubble,
    /// the answer as plain text on the surface.
    struct Line: Identifiable, Equatable, Codable {
        var id = UUID()
        var mine: Bool
        var text: String
        var done = true
        var failed: String?
        var at = Date()
        /// The page this question was asked from, when one went with it.
        var page: String?
        /// What the answer says that the page never did — an address, a
        /// phone number, an email (see AIPage.strays). Empty for an answer
        /// with no page behind it.
        var strays: [String] = []
        /// The page that went with this question had words written for a
        /// model to follow (see AIPage.addressesAI): the answer may have been
        /// steered by them, which the models never say themselves.
        var addressed = false
        /// How many pictures went with it. The pictures themselves are not
        /// written down: they were sent once, and the answer stands without
        /// them (see AIPage.shot).
        var shots = 0
        /// What the assistant did before it answered, in order — read off
        /// Dia's own card, one row each on a rail down the left (AIToolStep).
        /// Kept with the answer rather than thrown away, because "what did it
        /// do" is a question people ask after the fact.
        var steps: [AIToolStep] = []
    }

    /// A conversation as it is kept (Chats.swift): everything the page and
    /// the column need to draw it, and nothing that was only live.
    struct Record: Codable, Identifiable, Equatable {
        var id: UUID
        var title: String
        var at: Date
        var updated: Date
        var provider: String
        var model: String
        var lines: [Line]
    }

    let id: UUID
    let at: Date
    let provider: AIProvider
    let model: String

    @Published private(set) var title: String
    @Published private(set) var updated: Date
    @Published private(set) var lines: [Line] = []
    @Published var draft = ""
    /// What a provider off this Mac is sent, before it is agreed to.
    @Published private(set) var notice: String?
    @Published private(set) var trouble: String?
    /// Reading the page, or waiting on the answer.
    @Published private(set) var busy = false
    /// The page's own words, if it has any, so the column can say what goes.
    @Published private(set) var reading = false
    /// The card the assistant is asking in, while it waits for an answer:
    /// drawn in the column rather than as a sheet, so the page it is about
    /// stays in sight (AIToolAsk).
    let asking = AIToolAsk()
    /// The model's own line for the moment: what it is doing right now, as
    /// the tool call writes it (`say`, AITool.swift's words). One line and no
    /// history — what was done is on the page's own pages, and the record of
    /// it is AITool's `did`, not a list in the conversation.
    @Published private(set) var saying: String?
    /// Whether the page on screen goes with the next question: Dia's chip,
    /// and its cross takes it off for that question.
    @Published var attachPage = true
    /// Anything added with the plus — another tab, a file, a picture of a
    /// page — for the next question, and then gone.
    @Published var extras: [AIPage.Attachment] = []
    private var messages: [AIMessage] = []
    /// The window this conversation is in, so its tools act in the right one:
    /// set where the conversation is opened, and weak because the window owns
    /// the conversation, not the other way round.
    weak var browser: Browser?
    private let fence = AIPage.newFence()
    private var waiting: (ask: AIPage.Ask, tab: Tab?, shown: String)?
    private var task: Task<Void, Never>?

    init(provider: AIProvider, model: String) {
        id = UUID()
        at = Date()
        updated = at
        title = ""
        self.provider = provider
        self.model = model
    }

    init(record: Record) {
        id = record.id
        at = record.at
        updated = record.updated
        title = record.title
        provider = AIProvider(rawValue: record.provider) ?? .thisMac
        model = record.model
        lines = record.lines
        messages = Chat.rebuilt(from: record.lines)
    }

    var record: Record {
        Record(id: id, title: title, at: at, updated: updated,
               provider: provider.rawValue, model: model, lines: lines)
    }

    /// A conversation kept from last time, as what a new question follows:
    /// what you asked and what was answered. Not the pages — they were never
    /// written down.
    private static func rebuilt(from lines: [Line]) -> [AIMessage] {
        lines.compactMap { line in
            guard line.done, line.failed == nil, !line.text.isEmpty else { return nil }
            return AIMessage(role: line.mine ? .user : .assistant, text: line.text)
        }
    }

    var empty: Bool { lines.isEmpty && !busy }

    /// The name on the row and over the thread: the first thing asked, or
    /// what a summary was of.
    func rename(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        title = String(name.prefix(120))
        updated = Date()
    }

    func submit(from tab: Tab?) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy, notice == nil else { return }
        draft = ""
        let asked = String(question.prefix(4000))
        send(.question(asked), from: tab, shown: asked)
    }

    /// Dia's Summarize Page, as the first thing said here. Only the first:
    /// later on, a summary of a page is a question about it.
    func summarize(from tab: Tab?) {
        guard lines.isEmpty, !busy, notice == nil else { return }
        send(.summary, from: tab, shown: Localized("Summarize this page"))
    }

    private func send(_ ask: AIPage.Ask, from tab: Tab?, shown: String) {
        if !provider.isLocal, !Store.settings.bool(forKey: Localized("ai.told.\(provider.rawValue)")) {
            waiting = (ask, tab, shown)
            notice = AIAssist.notice(for: provider)
            return
        }
        go(ask, from: tab, shown: shown)
    }

    /// The notice read and agreed to: what was asked goes.
    func agree() {
        Store.settings.set(true, forKey: Localized("ai.told.\(provider.rawValue)"))
        notice = nil
        if let waiting { go(waiting.ask, from: waiting.tab, shown: waiting.shown) }
        waiting = nil
    }

    func disagree() {
        notice = nil
        waiting = nil
    }

    private func go(_ ask: AIPage.Ask, from tab: Tab?, shown: String) {
        // What goes with this question, fixed now: the page unless its chip
        // was taken off, then whatever the plus added, which is spent.
        let extras = self.extras
        let pageOn = attachPage
        self.extras = []
        lines.append(Line(mine: true, text: shown, page: tab?.title))
        lines.append(Line(mine: false, text: "", done: false))
        if title.isEmpty { title = Chat.name(for: ask, shown: shown, page: tab?.title) }
        busy = true
        trouble = nil
        reading = tab != nil || !extras.isEmpty
        updated = Date()
        let key = provider.isLocal ? nil : AIKeys.key(for: provider)
        let provider = self.provider
        let model = self.model
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            // The page goes with the question when there is one to read and
            // it may be read: a private tab's text never leaves this Mac, so
            // it is only ever attached for a model on this Mac.
            var reads: [AIPage.Read] = []
            let shy = tab?.shy == true
                || tab?.built.map { !$0.configuration.websiteDataStore.isPersistent } == true
            if pageOn, let tab, provider.isLocal || !shy, let found = await AIPage.read(tab) {
                reads.append(found)
            }
            reads += extras.compactMap(\.read)
            let shots = extras.compactMap(\.image)
            self.reading = false
            // A summary needs something to read; a question doesn't, and is
            // asked whether or not there was anything to attach.
            if ask == .summary, reads.isEmpty {
                self.withdraw(Localized("There's nothing on this page to read."))
                return
            }
            // The engine on this Mac reads words: a picture would be dropped
            // on the floor, so it is said rather than sent.
            if provider == .thisMac, !shots.isEmpty {
                self.withdraw(Localized("The model on this Mac can't look at pictures. Choose a model that can, in Settings › AI."))
                return
            }
            let asked = reads.isEmpty && shots.isEmpty
                ? shown
                : AIPage.opening(reads, ask, fence: self.fence, shots: shots.count)
            if reads.contains(where: { $0.addressed }), let last = self.lines.indices.last {
                self.lines[last].addressed = true
            }
            if !shots.isEmpty, let last = self.lines.indices.last {
                self.lines[last].shots = shots.count
            }
            self.messages.append(AIMessage(role: .user, text: asked, images: shots))
            // Tools are a cloud model's: the engine on this Mac takes words in
            // and gives words back, and skips any message that isn't text
            // (Engine/aura-ai-engine.cpp). Saying so is the honest thing; a
            // silently weaker assistant is not.
            let tools = self.tools(for: provider)
            let system = AIPage.system(fence: self.fence, tools: !tools.isEmpty)
            // The tools act in this window, on the page the question was asked
            // from — or, when it was asked from the page of its own, on the
            // tab the window has in front.
            guard let window = self.browser ?? Browsers.front ?? Browsers.primary else {
                self.withdraw(Localized("This conversation has no window to act in."))
                return
            }
            guard let acting = tab ?? window.active else {
                self.withdraw(Localized("Open a page before asking the assistant to act on one."))
                return
            }
            do {
                let added = try await AIToolLoop.run(messages: self.messages, provider: provider, model: model,
                                                     system: system, key: key, tools: tools,
                                                     browser: window, tab: acting,
                                                     stopped: { Task.isCancelled },
                                                     check: { tool, arguments in
                                                         await AIToolRisk.weigh(tool: tool, arguments: arguments,
                                                                                in: window, tab: acting)
                                                     },
                                                     event: { event in self.heard(event) })
                self.messages += added
                self.finish(nil, reads: reads)
            } catch {
                self.finish(error.localizedDescription, reads: reads)
            }
        }
    }

    /// Longer than any answer worth reading: a model talked into writing on
    /// and on is stopped, as the page's panel stopped it.
    static let longest = 16_000

    // MARK: - acting

    /// What the model may do, for this conversation: nothing unless the
    /// `ai.tools` switch is on and the provider can carry tool calls at all.
    ///
    /// The engine on this Mac cannot: it reads `content` as a string and skips
    /// any message that isn't one (Engine/aura-ai-engine.cpp), and a 1.7B
    /// model's tool calls are not worth the risk anyway. Saying so is the
    /// honest thing — a silently weaker assistant teaches nobody anything.
    private func tools(for provider: AIProvider) -> [AITool.Definition] {
        guard provider != .thisMac, Store.settings.object(forKey: "ai.tools") as? Bool == true else { return [] }
        return AITool.all
    }

    /// What the loop tells the panel as it goes.
    private func heard(_ event: AIToolLoop.Event) {
        switch event {
        case .wrote(let piece):
            guard !lines.isEmpty else { return }
            lines[lines.count - 1].text += piece
        case .saying(let said):
            // The model's line goes on the rail as it is written, so what you
            // watch while it works is what stays with the answer afterwards.
            saying = said
            if let last = lines.indices.last {
                lines[last].steps.append(.note(said))
            }
        case .did(let step):
            // A row of its own, kept with the answer: the rail is what "what
            // did it do" is answered with after the turn has ended.
            if let last = lines.indices.last {
                lines[last].steps.append(step)
            }
            saying = nil
        case .refused:
            saying = nil
        }
    }

    private func finish(_ failed: String?, reads: [AIPage.Read]) {
        reading = false
        busy = false
        saying = nil
        updated = Date()
        guard let index = lines.indices.last else { return }
        lines[index].done = true
        lines[index].failed = failed
        let answer = lines[index].text
        guard failed == nil, !answer.isEmpty else {
            if !messages.isEmpty { messages.removeLast() }
            return
        }
        // A picture went once: left in what follows, every question after it
        // would send it again.
        if let question = messages.lastIndex(where: { $0.role == .user }), !messages[question].images.isEmpty {
            messages[question].images = []
        }
        // Checked away from the window's thread: a long answer is a long look.
        guard !reads.isEmpty else { return }
        let read = AIPage.together(reads)
        let id = lines[index].id
        Task.detached(priority: .userInitiated) { [self] in
            let strays = AIPage.strays(in: answer, from: read)
            guard !strays.isEmpty else { return }
            await MainActor.run { self.note(strays, on: id) }
        }
    }

    /// What the check found, on the line it belongs to.
    private func note(_ strays: [String], on id: UUID) {
        guard let at = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[at].strays = strays
    }

    /// A thing asked that turned out to have nothing to say: the question
    /// comes back off the thread, and what is wrong is said where it stood.
    private func withdraw(_ why: String) {
        reading = false
        busy = false
        saying = nil
        if lines.count >= 2 { lines.removeLast(2) }
        trouble = why
    }

    func stop() {
        task?.cancel()
        task = nil
        guard busy else { return }
        busy = false
        reading = false
        updated = Date()
        if let last = lines.indices.last { lines[last].done = true }
        // A half-answer isn't what follows: the question stays on the thread,
        // and only it goes into the next request again.
        if !messages.isEmpty { messages.removeLast() }
    }

    /// A conversation with something already said in it, for a picture of the
    /// column or the page (bench ai picture) — never for a real one.
    static func picture(provider: AIProvider = .ollama, model: String = "llama3.3") -> Chat {
        let chat = Chat(provider: provider, model: model)
        // The chips Dia's field wears: a file and a picture, taken off with
        // their crosses.
        chat.extras = [
            AIPage.Attachment(kind: .file, title: "note.txt", detail: "Desktop",
                              read: AIPage.shaped(title: "note.txt", url: nil, text: "…", links: [], source: "file")),
            AIPage.Attachment(kind: .shot, title: "Screenshot", detail: "example.com", image: Data([0xFF])),
        ]
        chat.title = "Which file holds the theme colours?"
        chat.lines = [
            Line(mine: true, text: "Of these three files, which one holds the theme colours? And why split it out?",
                 page: "Aura"),
            Line(mine: false, text: "Design.swift does. Palette and Metrics both live in it — one for colour, one for size — and other files only refer to the names, never write a colour of their own.",
                 steps: [
                    .note("先看一下设计文件都写了什么。"),
                    AIToolStep.named("snapshot", detail: "Read the page."),
                    AIToolStep.done("navigate", arguments: AIToolArguments(text: #"{"url":"https://www.bilibili.com"}"#),
                                    did: "Opened https://www.bilibili.com/.", failed: false),
                    .note("页面已经打开，在读它的内容。"),
                 ]),
            // And one still being written, so a picture shows what stands
            // where an answer is coming — the rail as it grows, and the dots
            // under it.
            Line(mine: false, text: "", done: false, steps: [
                .note("我在查浙江传媒学院的官方信息。"),
                AIToolStep.done("navigate", arguments: AIToolArguments(text: #"{"url":"https://www.cuz.edu.cn"}"#),
                                did: "Opened https://www.cuz.edu.cn/.", failed: false),
            ]),
        ]
        return chat
    }

    /// The name a conversation goes by until it is renamed: what was asked,
    /// or what a summary was of.
    private static func name(for ask: AIPage.Ask, shown: String, page: String?) -> String {
        switch ask {
        case .summary:
            let of = page.flatMap { $0.isEmpty ? nil : $0 } ?? Localized("this page")
            return Localized("Summary · \(of)")
        case .question:
            return String(shown.replacingOccurrences(of: "\n", with: " ").prefix(60))
        }
    }
}

extension Browser {
    /// This window's conversations (see Chats.swift): the profile's, made
    /// once and shared by every window of it.
    var chats: Chats { Profiles.chats(profileID) }

    /// ⌘⇧A, the column's foot and View › Chat: the conversation in the column
    /// beside the page, opened or put away.
    func toggleChat() {
        if chatUp { closeChat() } else { openChat() }
    }

    /// The panel is the conversation's: Dia keeps its assistant beside the
    /// page, not over it.
    var chatUp: Bool { sidePanelShown && sidePanel == .ai }

    /// What the conversation still needs before it can answer, in a
    /// sentence — nil when it can. The column says it where it stands and
    /// offers the page that fixes it, rather than the door doing nothing.
    var chatSetup: String? {
        guard prefs.ai else { return Localized("AI is off. Turn it on in Settings › AI.") }
        guard let provider = prefs.aiProvider else { return Localized("Choose where the AI runs, in Settings › AI.") }
        if provider == .thisMac, AIEngine.shared.state != .ready { return Localized("The model isn't on this Mac yet.") }
        if provider == .custom, AIProvider.customAddress.isEmpty {
            return Localized("Give your own model its address in Settings › AI.")
        }
        guard !prefs.aiModel(for: provider).isEmpty else { return Localized("Choose a model for \(provider.name)") }
        guard provider.isLocal || AIKeys.hint(for: provider) != nil else {
            return Localized("No key for \(provider.name) yet")
        }
        return nil
    }

    /// The conversation in front: this tab's own, and a new one for a tab
    /// that has never asked anything.
    @discardableResult
    func openChat() -> Chat? {
        // Off entirely until the add-on is in the build. Everything else the
        // conversation needs is said inside the column (chatSetup), so the
        // door always opens onto something rather than doing nothing.
        guard AI.shipped || Store.testing else { return nil }
        // Not the last conversation this profile had — that one belongs to
        // the tab it was had on, and is in the list to be gone back to. Dia
        // opens the assistant on the tab's own chat, and on a tab that has
        // none it opens an empty one, not somebody else's afternoon.
        let chat = self.chat ?? newChat()
        showChat()
        return chat
    }

    /// The column beside the page, with the conversation in it. One column,
    /// and one thing in it: an extension's or a site's panel gives it up, as
    /// Chrome shows one panel at a time.
    func showChat() {
        if case .page(_, _, let bound?) = sidePanel { SidePanelPages.shared.unbind(bound, in: self) }
        SidePanelPages.shared.drop(in: self)
        sidePanel = .ai
        sidePanelShown = true
    }

    /// A conversation of its own, in front, belonging to the tab in front:
    /// New Chat, or the first word in a tab that has none.
    @discardableResult
    func newChat() -> Chat {
        let provider = prefs.aiProvider ?? .thisMac
        let chat = chats.make(provider: provider, model: prefs.aiModel(for: provider))
        // Setting it binds it to the tab in front (Browser.chat).
        self.chat = chat
        return chat
    }

    /// The tab in front brought its conversation with it — the one it was
    /// asked on, or a new empty one when the column is up and this tab has
    /// never been asked anything. A column that is put away makes nothing:
    /// a chat is a thing that exists once something has been said in it.
    ///
    /// The page of them all is the library and not a page a conversation
    /// hangs off: it shows the one in front (ChatsPanel), so landing on it
    /// keeps that one rather than starting a chat nothing is said in.
    func takeUpChat() {
        if pageTab(.chat)?.id == activeID { return }
        if active?.chat == nil, chatUp { newChat() } else { chat = active?.chat }
    }

    /// A conversation taken out of the list is taken off every tab that had
    /// it, so a tab cannot go on showing what was just forgotten.
    func forgetChat(_ chat: Chat) {
        for tab in tabs where tab.chat?.id == chat.id { tab.chat = nil }
        if self.chat?.id == chat.id { self.chat = nil }
    }

    /// Forget All: every conversation this window's tabs had.
    func forgetChats() {
        for tab in tabs { tab.chat = nil }
        chat = nil
    }

    /// The conversation put away, and not thrown away: it is in the list, and
    /// what it was answering carries on while you read something else.
    func closeChat() {
        if case .ai = sidePanel { closeSidePanel() }
    }

    /// Dia's expand: the conversation into a page of its own, which is a tab
    /// like Settings and History are (InternalPages.swift).
    func expandChat() {
        let chat = self.chat ?? openChat()
        show(InternalPage(.chat))
        // Dia's expand is the panel turning into a tab: the conversation the
        // column had is the one the page shows, rather than an empty one of
        // its own making.
        self.chat = chat
        if case .ai = sidePanel { closeSidePanel() }
    }
}
