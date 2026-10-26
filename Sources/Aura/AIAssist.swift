import SwiftUI

// The AI add-on as you meet it: Summarize Page and Ask About This Page…, the
// notice a provider off this Mac is shown once before it is used, and
// Settings › AI.
//
// The answers themselves are the window's conversation's (Chat.swift): a
// summary is its first thing said, a question is a question, and both open in
// the column beside the page — where Dia keeps its assistant — with the
// page's own text going along as what to read (AIPage), never as orders. What
// is left here is the door (which page may be asked about, and what is said
// before a provider off this Mac is used), the words of that notice, and the
// page that sets the whole thing up.

enum AIAssist {
    /// What a provider off this Mac is sent, said once, the first time it is
    /// used — and a word on what it does with it where that matters.
    ///
    /// A sentence to a key, so a translator can put them in another order or
    /// say them shorter: the last card that was built by pasting English
    /// together came out in English inside a Chinese window. `{1}` is the
    /// host it goes to.
    static func notice(for provider: AIProvider) -> String {
        let to = provider.host.isEmpty ? provider.name : provider.host
        var said = [
            provider == .openRouter
                ? Localized("When you ask, Aura sends this page's text, its address and your question to \(to), which passes them to the model's provider.")
                : Localized("When you ask, Aura sends this page's text, its address and your question to \(to)."),
            Localized("Their terms and privacy policy apply."),
            Chats.keeps
                ? Localized("Nothing is sent until you ask, never from a private tab, and what you asked and were answered stays on this Mac.")
                : Localized("Nothing is sent until you ask, never from a private tab, and Aura keeps no copy."),
        ].joined(separator: " ")
        switch provider {
        case .gemini:
            said += "\n\n" + Localized("On Gemini's free tier, outside the EEA, Switzerland and the UK, Google may use this to improve its products, and people may read it. Don't use it on sensitive pages.")
        case .openRouter:
            said += "\n\n" + Localized("Aura asks OpenRouter to use only providers that keep nothing (zero data retention).")
        default:
            break
        }
        return said
    }
}

extension Browser {
    /// View › Summarize Page: the page in front, read, and the conversation's
    /// first words a summary of it.
    func summarizePage() {
        guard let tab = askablePage() else { return }
        guard let where_ = whereAI() else { return }
        let chat = chatFor(where_.provider, model: where_.model)
        showChat()
        chat.summarize(from: tab)
    }

    /// View › Ask About This Page…: the same conversation, with the field in
    /// front and the page waiting on the chip above it.
    func askAboutPage() {
        guard askablePage() != nil else { return }
        guard whereAI() != nil else { return }
        // The column, with the field in it: the page goes with whatever is
        // typed, as the chip above the field says (ChatComposer).
        openChat()
    }

    /// The page in front, if it is one the add-on may ask about: a web page,
    /// never a file or an extension's, and a private one only of a model on
    /// this Mac.
    private func askablePage() -> Tab? {
        guard AI.shipped || Store.testing, let tab = active, tab.isWeb else { return nil }
        guard let scheme = tab.pageAddress?.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            announce(Localized("AI works on web pages"))
            return nil
        }
        let shy = tab.shy || tab.built.map { !$0.configuration.websiteDataStore.isPersistent } == true
        guard !shy || prefs.aiProvider?.isLocal == true else {
            announce(Localized("In a private tab, only an AI on this Mac"))
            return nil
        }
        return tab
    }

    /// Where an answer would come from, once everything it needs is there.
    /// When it isn't, says what is missing and opens the page that fixes it:
    /// the model, the key, the address, the download.
    func whereAI() -> (provider: AIProvider, model: String)? {
        guard prefs.ai, let provider = prefs.aiProvider else {
            settingsPage = .ai
            tuning = true
            announce(prefs.ai ? Localized("Choose where the AI runs") : Localized("Turn on AI in Settings › AI"))
            return nil
        }
        if provider == .thisMac, AIEngine.shared.state != .ready {
            settingsPage = .ai
            tuning = true
            announce(Localized("The model isn't on this Mac yet"))
            return nil
        }
        if provider == .custom, AIProvider.customAddress.isEmpty {
            settingsPage = .ai
            tuning = true
            announce(Localized("Give your own model its address in Settings › AI"))
            return nil
        }
        let model = prefs.aiModel(for: provider)
        guard !model.isEmpty else {
            settingsPage = .ai
            tuning = true
            announce(Localized("Choose a model for \(provider.name)"))
            return nil
        }
        guard provider.isLocal || AIKeys.hint(for: provider) != nil else {
            settingsPage = .ai
            tuning = true
            announce(Localized("No key for \(provider.name) yet"))
            return nil
        }
        return (provider, model)
    }

    /// The conversation a door starts: the one in front when it has said
    /// nothing yet and answers from the same place, and a new one otherwise
    /// — a summary of another page is its own conversation.
    private func chatFor(_ provider: AIProvider, model: String) -> Chat {
        if let open = chat, open.empty, open.provider == provider, open.model == model { return open }
        let made = chats.make(provider: provider, model: model)
        chat = made
        return made
    }
}

// MARK: - Settings › AI

struct AISettings: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    /// Drawn off screen, for a picture: menus and fields stood in for.
    var drawn = false
    @State private var pasted = ""
    @State private var hint: String?
    @State private var models: [String] = []
    @State private var looking = false
    @ObservedObject private var engine = AIEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Use AI on pages", "Summarize a page, or ask about it, from the View menu. Nothing is sent until you ask") {
                    Switch(on: $prefs.ai)
                }
            }
            if prefs.ai {
                Card {
                    Line("Where it runs", place) {
                        if drawn {
                            Stand(prefs.aiProvider.map { $0.isLocal ? "\($0.name), on this Mac" : $0.name } ?? "Choose…", menu: true)
                        } else {
                        Picker("", selection: Binding(get: { prefs.aiProvider }, set: { prefs.aiProvider = $0 })) {
                            Text("Choose…").tag(AIProvider?.none)
                            ForEach(AIProvider.allCases.filter { $0 != .thisMac || engine.available || prefs.aiProvider == .thisMac }) { provider in
                                Text(provider == .thisMac ? provider.name : provider.isLocal ? "\(provider.name), on this Mac" : provider.name)
                                    .tag(AIProvider?.some(provider))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        }
                    }
                    if let provider = prefs.aiProvider {
                        Rule()
                        if provider == .thisMac { onThisMac }
                        else if provider == .custom { ownModel(provider) }
                        else if provider.isLocal { localModel(provider) }
                        else { key(provider); Rule(); cloudModel(provider) }
                    }
                }
                .onChange(of: prefs.aiProvider) { _, _ in
                    // A key typed for one provider is never saved for another.
                    pasted = ""
                    refresh()
                }
                .onChange(of: prefs.aiCustomAddress) { _, _ in
                    pasted = ""
                    refresh()
                }
                .onChange(of: prefs.keepsChats) { _, _ in browser.chats.save() }
                .onAppear(perform: refresh)
                Card {
                    Line("Keep chats", "Every conversation saved in this profile, for the Chats page. Off, and it goes when the window closes") {
                        Switch(on: $prefs.keepsChats)
                    }
                    Rule()
                    Line("Forget every key", "Deletes them from this Mac's keychain") {
                        Pill("Forget") {
                            AIKeys.forgetAll()
                            refresh()
                            browser.announce("Keys forgotten")
                        }
                    }
                }
            }
        }
    }

    /// The model here: downloaded when you say, checked, prepared once.
    @ViewBuilder
    private var onThisMac: some View {
        let size = ByteCountFormatter.string(fromByteCount: engine.downloadSize, countStyle: .file)
        if AIEngine.translated {
            Line("Model", "Needs the Apple Silicon version of Aura — this copy runs translated") { EmptyView() }
        } else {
            switch engine.state {
            case .absent:
                Line("Model", Localized("\(AIEngine.model.name), downloaded once (\(size)) and checked. Nothing leaves this Mac")) {
                    Pill("Download", filled: true) { engine.install() }
                }
            case .downloading(let done):
                Line("Model", Localized("Downloading… \(Int(done * 100))%")) {
                    Pill("Cancel") { engine.cancelInstall() }
                }
            case .preparing:
                Line("Model", "Preparing it for this Mac — about twenty seconds, once") { EmptyView() }
            case .ready:
                Line("Model", Localized("\(AIEngine.model.name), on this Mac. Nothing leaves it")) {
                    Pill("Remove") { engine.remove() }
                }
            case .failed(let why):
                Line("Model", why) {
                    Pill("Try Again") { engine.install() }
                }
            }
        }
    }

    private var place: String {
        guard let provider = prefs.aiProvider else { return "A provider you have a key with, an app on this Mac, or an API of your own" }
        if provider == .custom, AIProvider.customAddress.isEmpty {
            return "An API of your own: its address, its model, and a key unless it runs on this Mac"
        }
        return provider.isLocal
            ? "Nothing leaves this Mac. Also in private tabs"
            : Localized("Your key, kept in \(AIKeys.vault.described), sent only to \(provider.host). Never from a private tab")
    }

    @ViewBuilder
    private func key(_ provider: AIProvider) -> some View {
        if let hint {
            Line("Key", Localized("\(hint), in \(AIKeys.vault.described)")) {
                Pill("Forget") {
                    AIKeys.forget(provider)
                    refresh()
                }
            }
        } else {
            Line("Key", "Paste your API key") {
                HStack(spacing: 6) {
                    SecureField("", text: $pasted, prompt: Text("Key").foregroundStyle(Palette.faint))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 130)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .onSubmit { save(provider) }
                    Pill("Save") { save(provider) }
                }
            }
        }
    }

    // MARK: - an API of your own

    /// Four things, and the key: what it is called, where it answers, how its
    /// requests are written, and which model — the last one listable from the
    /// API itself, as an app on this Mac lists its own.
    @ViewBuilder
    private func ownModel(_ provider: AIProvider) -> some View {
        Line("Name", "What it is called here, and under every answer") {
            field(prefs.aiCustomName, prompt: "Custom", width: 170) { prefs.aiCustomName = $0 }
        }
        Rule()
        Line("Address", "The API's root: requests go to its /chat/completions, or /messages for Anthropic's shape. https, or http to this Mac") {
            field(prefs.aiCustomAddress, prompt: "https://api.example.com/v1", width: 210) { prefs.aiCustomAddress = $0 }
        }
        Rule()
        Line("Format", "How requests are written") {
            if drawn {
                Stand(prefs.aiCustomWire == "anthropic" ? "Anthropic" : "OpenAI", menu: true, width: 110)
            } else {
                Picker("", selection: Binding(get: { prefs.aiCustomWire },
                                              set: { prefs.aiCustomWire = $0; refresh() })) {
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        Rule()
        if models.isEmpty {
            Line("Model", looking ? Localized("Asking \(provider.name)…") : "Type the model's name, or look up what the API offers") {
                HStack(spacing: 6) {
                    field(prefs.aiModels[provider.rawValue] ?? "", prompt: "Model", width: 150) {
                        prefs.setAIModel($0, for: provider)
                    }
                    Pill(looking ? "Looking…" : "Look Up") { refresh() }
                }
            }
        } else {
            Line("Model", Localized("From \(provider.name)")) {
                Picker("", selection: Binding(get: { prefs.aiModel(for: provider) },
                                              set: { prefs.setAIModel($0, for: provider) })) {
                    Text("Choose…").tag("")
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        Rule()
        key(provider)
    }

    /// A small plain field, the size of the ones this page already uses.
    private func field(_ text: String, prompt: String, width: CGFloat,
                       set: @escaping (String) -> Void) -> some View {
        TextField("", text: Binding(get: { text }, set: set),
                  prompt: Text(prompt).foregroundStyle(Palette.faint))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .frame(width: width)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func cloudModel(_ provider: AIProvider) -> some View {
        Line("Model", Localized("Leave empty for \(provider.defaultModel)")) {
            if drawn {
                Stand(prefs.aiModels[provider.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? provider.defaultModel, width: 170)
            } else {
            TextField("", text: Binding(get: { prefs.aiModels[provider.rawValue] ?? "" },
                                        set: { prefs.setAIModel($0, for: provider) }),
                      prompt: Text(provider.defaultModel).foregroundStyle(Palette.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 170)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    /// A menu or a field, as a picture shows it.
    private struct Stand: View {
        let text: String
        var menu = false
        var width: CGFloat?
        init(_ text: String, menu: Bool = false, width: CGFloat? = nil) { self.text = text; self.menu = menu; self.width = width }
        var body: some View {
            HStack(spacing: 5) {
                Text(text.localized).font(.system(size: 12)).foregroundStyle(menu ? Palette.ink : Palette.faint)
                if menu { Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted) }
            }
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(menu ? Palette.ground : Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(menu ? Palette.hairline : .clear, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func localModel(_ provider: AIProvider) -> some View {
        if models.isEmpty {
            Line("Model", looking ? Localized("Asking \(provider.name)…") : Localized("\(provider.name) isn't running, or has no model yet")) {
                Pill("Look Again") { refresh() }
            }
        } else {
            Line("Model", Localized("From \(provider.name) on this Mac")) {
                Picker("", selection: Binding(get: { prefs.aiModel(for: provider) }, set: { prefs.setAIModel($0, for: provider) })) {
                    Text("Choose…").tag("")
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private func save(_ provider: AIProvider) {
        let key = pasted
        pasted = ""
        switch AIKeys.save(key, for: provider) {
        case .kept: browser.announce("Key kept in the keychain")
        case .unavailable: browser.announce("This copy of Aura can't keep keys")
        case .failed: browser.announce("The key wasn't kept")
        }
        refresh()
    }

    /// Looked at when the page is: an app on this Mac, or the API of your own,
    /// is asked for its models only now, never in the background.
    private func refresh() {
        guard let provider = prefs.aiProvider else { return }
        hint = provider.isLocal ? nil : AIKeys.hint(for: provider)
        models = []
        let askable = provider.isLocal
            || (provider == .custom && !AIProvider.customAddress.isEmpty && AIKeys.hint(for: provider) != nil)
        guard askable else { return }
        looking = true
        Task { @MainActor in
            models = await AIClient.shared.models(provider)
            looking = false
        }
    }
}
