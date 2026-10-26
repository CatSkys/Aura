import SwiftUI

// The conversation that belongs to the window rather than to a page: one
// thread you can carry from tab to tab, which is what Dia's assistant is.
// The page you are on goes with each question when it can be read — its
// text, its address — and a private tab's never does, by any provider off
// this Mac.
//
// A page's own conversation is `Assistant`'s (AIAssist.swift): it dies with
// the page and with the panel. This one lives as long as the window, and is
// kept nowhere: close the window and it is gone, as the page's is when you
// close it.
//
// What is asked and answered here is the same machinery — AIPage's text,
// AIClient's or AIEngine's stream — so the two surfaces differ in how long
// they live, not in what they can do.

@MainActor
final class Chat: ObservableObject, Identifiable {
    /// One thing said, by you or to you. Dia's grammar: yours in a bubble,
    /// the answer as plain text on the surface.
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        var text: String
        var done = true
        var failed: String?
        var at = Date()
        /// The page this question was asked from, when one went with it.
        var page: String?
    }

    let id = UUID()
    let provider: AIProvider
    let model: String

    @Published private(set) var lines: [Line] = []
    @Published var draft = ""
    /// What a provider off this Mac is sent, before it is agreed to.
    @Published private(set) var notice: String?
    @Published private(set) var trouble: String?
    /// Reading the page, or waiting on the answer.
    @Published private(set) var busy = false
    /// The page's own words, if it has any, so the panel can say what goes.
    @Published private(set) var reading = false

    private var messages: [AIMessage] = []
    private let fence = AIPage.newFence()
    private var waiting: (question: String, tab: Tab?)?
    private var task: Task<Void, Never>?

    init(provider: AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// Where it ran, for the foot of every answer — the same sentence the
    /// page's panel puts there.
    var place: String {
        provider == .thisMac ? "on this Mac · \(model)"
            : provider.isLocal ? "on this Mac · \(provider.name) · \(model)" : "sent to \(provider.name) · \(model)"
    }

    var empty: Bool { lines.isEmpty && !busy }

    func submit(from tab: Tab?) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy, notice == nil else { return }
        draft = ""
        ask(String(question.prefix(4000)), from: tab)
    }

    private func ask(_ question: String, from tab: Tab?) {
        if !provider.isLocal, !Store.settings.bool(forKey: Localized("ai.told.\(provider.rawValue)")) {
            waiting = (question, tab)
            notice = AIAssist.notice(for: provider)
            return
        }
        send(question, from: tab)
    }

    /// The notice read and agreed to: what was asked goes.
    func agree() {
        Store.settings.set(true, forKey: Localized("ai.told.\(provider.rawValue)"))
        notice = nil
        if let waiting { send(waiting.question, from: waiting.tab) }
        waiting = nil
    }

    func disagree() {
        notice = nil
        waiting = nil
    }

    private func send(_ question: String, from tab: Tab?) {
        lines.append(Line(mine: true, text: question, page: tab?.title))
        lines.append(Line(mine: false, text: "", done: false))
        busy = true
        trouble = nil
        reading = true
        let key = provider.isLocal ? nil : AIKeys.key(for: provider)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            // The page goes with the question when there is one to read and
            // it may be read: a private tab's text never leaves this Mac, so
            // it is only ever attached for a model on this Mac.
            var asked = question
            // The same test the page's panel makes (AIAssist.startAssistant):
            // a private tab is one with no persistent store behind it.
            let shy = tab?.shy == true
                || tab?.built.map { !$0.configuration.websiteDataStore.isPersistent } == true
            if let tab, self.provider.isLocal || !shy, let read = await AIPage.read(tab) {
                asked = AIPage.opening(read, .question(question), fence: self.fence)
            }
            self.reading = false
            self.messages.append(AIMessage(role: .user, text: asked))
            let stream = self.provider == .thisMac
                ? AIEngine.shared.stream(system: AIPage.system(fence: self.fence), messages: self.messages)
                : AIClient.shared.stream(self.provider, model: self.model,
                                         system: AIPage.system(fence: self.fence),
                                         messages: self.messages, key: key)
            do {
                for try await piece in stream {
                    guard !self.lines.isEmpty else { return }
                    self.lines[self.lines.count - 1].text += piece
                    if self.lines[self.lines.count - 1].text.count > Chat.longest { break }
                }
                self.finish(nil)
            } catch {
                self.finish(error.localizedDescription)
            }
        }
    }

    /// Longer than any answer worth reading: a model talked into writing on
    /// and on is stopped, as the page's panel stops it.
    static let longest = 16_000

    private func finish(_ failed: String?) {
        reading = false
        busy = false
        guard let index = lines.indices.last else { return }
        lines[index].done = true
        lines[index].failed = failed
        if failed == nil, !lines[index].text.isEmpty {
            messages.append(AIMessage(role: .assistant, text: lines[index].text))
        } else if !messages.isEmpty {
            messages.removeLast()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if busy { finish(nil) }
    }

    func clear() {
        stop()
        lines = []
        messages = []
        trouble = nil
    }

    /// A conversation with something already said in it, for a picture of
    /// the panel (bench ai picture) — never for a real one.
    static func picture(provider: AIProvider = .ollama, model: String = "llama3.3") -> Chat {
        let chat = Chat(provider: provider, model: model)
        chat.lines = [
            Line(mine: true, text: "这三个文件里，哪个管主题色？顺便说说为什么拆开。",
                 page: "Aura"),
            Line(mine: false, text: "是 Design.swift。Palette 与 Metrics 都在它里面，一个管颜色、一个管尺寸，别的文件只引用名字，不再自己写色值。"),
        ]
        return chat
    }
}

extension Browser {
    /// The side of the window the conversation opens on, opened or closed.
    /// Off entirely until the add-on is on (Settings › AI), as the page's
    /// panel is.
    func toggleChat() {
        if chat != nil { closeChat() } else { openChat() }
    }

    /// What the conversation still needs before it can answer, in a
    /// sentence — nil when it can. The panel says it where it stands and
    /// offers the page that fixes it, rather than the door doing nothing.
    var chatSetup: String? {
        guard prefs.ai else { return "AI is off. Turn it on in Settings › AI." }
        guard let provider = prefs.aiProvider else { return "Choose where the AI runs, in Settings › AI." }
        if provider == .thisMac, AIEngine.shared.state != .ready { return "The model isn't on this Mac yet." }
        guard !prefs.aiModel(for: provider).isEmpty else { return Localized("Choose a model for \(provider.name)") }
        guard provider.isLocal || AIKeys.hint(for: provider) != nil else {
            return Localized("No key for \(provider.name) yet")
        }
        return nil
    }

    func openChat() {
        // Off entirely until the add-on is in the build. Everything else the
        // conversation needs is said inside the panel (chatSetup), so the
        // door always opens onto something rather than doing nothing.
        guard AI.shipped || Store.testing else { return }
        if chat != nil { return }
        // One column beside the page: the conversation and the side panel
        // cannot both be in it, so the one being opened takes it.
        if sidePanelShown, sidePanel != nil {
            closeSidePanel()
            announce("Side panel closed")
        }
        else if let open = assisting { open.stop(); assisting = nil }
        let provider = prefs.aiProvider ?? .thisMac
        chat = Chat(provider: provider, model: prefs.aiModel(for: provider))
    }

    func closeChat() {
        chat?.stop()
        chat = nil
    }
}
