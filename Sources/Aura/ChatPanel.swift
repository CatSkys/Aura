import SwiftUI

// The conversation drawn: one set of pieces for the column beside the page
// (ChatPane) and for the page of its own (ChatsPanel), so the two are the
// same thing at two sizes rather than two designs.
//
// What is Dia's here, read off the application:
//   · the answer is written, not boxed: 15 points on the page's white, its
//     headings heavier, its bullets indented, a quote ruled down the left;
//   · what you asked is a bubble tinted with the space's colour, 17 round,
//     set to the right;
//   · a sphere breathes while it thinks;
//   · the field is one floating pill near the bottom: what you type, then
//     small doors — a plus, a microphone — and the filled circle to send;
//   · the head says what this is: a bubble, the conversation's name, and the
//     doors that make another, open it as a page, or put it away.
// Everything else — the ring, the inks, the ring round the field — is the
// browser's own.

// MARK: - the writing

/// What was said, once and again: yours in a bubble, the answer as text, the
/// sphere where an answer is coming.
struct ChatThread: View {
    @ObservedObject var chat: Chat
    /// The space's own colour, for the bubble: the column and the page take
    /// the window's, so a conversation looks the same in both.
    var seed: Color = Palette.Chat.muted
    /// A page is in front to be read, for the words of the empty state.
    var pageOpen = true
    /// For a picture (bench ai picture): the scroll view stood in for.
    var drawn = false
    /// The widest the writing gets: a paragraph, never the whole window.
    var column: CGFloat = 760
    /// Room under it for the field floating over the foot.
    var foot: CGFloat = 140

    var body: some View {
        if drawn {
            writing.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, foot)
        } else {
            ScrollViewReader { scroller in
                ScrollView {
                    writing
                        .frame(maxWidth: column, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, foot)
                    Color.clear.frame(height: 1).id("foot")
                }
                .onChange(of: chat.lines.count) { _, _ in scroll(scroller) }
                .onChange(of: chat.lines.last?.text) { _, _ in scroll(scroller) }
            }
        }
    }

    @ViewBuilder private var writing: some View {
        VStack(alignment: .leading, spacing: 18) {
            if chat.empty {
                empty
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(chat.lines) { line in row(line) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(_ line: Chat.Line) -> some View {
        if line.mine {
            HStack(spacing: 0) {
                Spacer(minLength: 60)
                Text(verbatim: line.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.Chat.ink)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(LinearGradient(colors: [seed.opacity(0.12), seed.opacity(0.09)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
            }
        } else if line.text.isEmpty, !line.done {
            // The model's own line while it acts (`say`), then what the
            // browser is doing for it: one line, in one place, replaced as the
            // next thing starts and gone when the turn ends.
            HStack(spacing: 0) {
                Pulsing(chat.saying ?? (chat.reading ? Localized("Reading this page…") : Localized("Thinking…")))
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if line.addressed {
                    caution(Localized("This page has text written for an AI to follow. The answer may have been steered by it."))
                }
                Wrote(line.text)
                if let failed = line.failed {
                    Text(verbatim: failed.localized)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.Chat.faint)
                } else if line.done {
                    if !line.strays.isEmpty { strays(line.strays) }
                    marks(line)
                }
            }
        }
    }

    /// What the answer said that the page never did: the check the page's
    /// panel made, kept with the conversation.
    private func strays(_ found: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .medium))
            Text(verbatim: Localized("Not on the page: ") + found.joined(separator: ", "))
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.Chat.muted)
        .padding(8)
        .background(Palette.Chat.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func caution(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .medium))
            Text(verbatim: text)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.Chat.muted)
        .padding(8)
        .background(Palette.Chat.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// What is under an answer: the copy, and when it was said. Dia's thumbs
    /// are not there — nothing counts them — and neither is the sentence
    /// naming where the answer ran, which is under Settings › AI where it can
    /// be changed.
    private func marks(_ line: Chat.Line) -> some View {
        HStack(spacing: 12) {
            markDoor("square.on.square") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.text, forType: .string)
            }
            Text(line.at.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(Palette.Chat.faint)
            Spacer(minLength: 0)
        }
    }

    private func markDoor(_ icon: String, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Palette.Chat.faint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Nothing asked yet: the two lines, and no card over them. Dia opens its
    /// chat with a tip that names a Capture Tool and asks what the page is
    /// about; the field below already says what to do, and a card explaining
    /// a conversation that hasn't started is in the way of starting it.
    private var empty: some View {
        VStack(spacing: 8) {
            Text("Ask about something you see")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.Chat.ink)
            Text(pageOpen
                 ? Localized("Aura reads the page you're on, and nothing is sent until you ask")
                 : Localized("Open a page and Aura can read it with your question"))
                .font(.system(size: 15))
                .foregroundStyle(Palette.Chat.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func scroll(_ scroller: ScrollViewProxy) {
        withAnimation(Motion.quick) { scroller.scrollTo("foot", anchor: .bottom) }
    }
}

/// What stands where an answer is coming: the words, breathing. The sphere
/// Dia breathes there was a black ball sitting in a column of writing — it
/// said nothing the words didn't, and it drew the eye to itself. With less
/// motion asked for, the words hold still.
private struct Pulsing: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var faint = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.Chat.muted)
            .opacity(faint ? 0.4 : 1)
            .animation(calm ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: faint)
            .onAppear { if !calm { faint = true } }
    }
}

// MARK: - the field

/// One floating pill: what you type, a plus, the microphone, the send — and,
/// above it, the page that will go along with what is typed.
struct ChatComposer: View {
    @ObservedObject var browser: Browser
    @ObservedObject var chat: Chat
    /// As wide as the writing above it.
    var column: CGFloat = 760
    /// For a picture: the field stood in for.
    var drawn = false

    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let setup = browser.chatSetup {
                setupCard(setup)
            } else if let notice = chat.notice {
                noticeCard(notice)
            } else if let trouble = chat.trouble {
                troubleCard(trouble)
            } else {
                field
            }
        }
        .frame(maxWidth: column)
        .onAppear { if !drawn { typing = true } }
    }

    // One card, as Dia's is: what goes with the question on chips that can
    // be taken off, the field, and its doors along the foot — the plus at the
    // left for another tab, a file or a picture; the send at the right.
    private var field: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chips.isEmpty { chipRow }
            if drawn {
                Text(verbatim: placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.Chat.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $chat.draft,
                          prompt: Text(verbatim: placeholder).foregroundStyle(Palette.Chat.faint),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.Chat.ink)
                    .lineLimit(1...6)
                    .focused($typing)
                    .onSubmit { send() }
                    .disabled(chat.busy)
            }
            HStack(spacing: 14) {
                if drawn {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.Chat.muted)
                } else {
                    Menu {
                        addItems
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.Chat.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Localized("Add a Tab, a File or a Picture"))
                }
                Spacer(minLength: 0)
                door("camera", help: Localized("Screenshot This Page")) { shot() }
                Button {
                    if chat.busy { chat.stop() } else { send() }
                } label: {
                    Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.Chat.raised)
                        .frame(width: 28, height: 28)
                        .background(ready ? Palette.Chat.ink : Palette.Chat.faint, in: Circle())
                }
                .buttonStyle(.plain)
                .help(chat.busy ? Localized("Stop") : Localized("Send   ⏎"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Palette.Chat.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.Chat.edge, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.09), radius: 12, y: 3)
    }

    /// Dia's field says what it is about: with a page on it, a question about
    /// that page; without one, another question.
    private var placeholder: String {
        if chat.attachPage, chipPage != nil { return Localized("Ask a question about this page…") }
        return Localized("Ask another question…")
    }

    private func door(_ icon: String, help: String, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.Chat.muted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - what goes with the question

    /// The page on screen, then what the plus added: each a chip whose cross
    /// takes it off this question.
    private var chips: [AIPage.Attachment] {
        var out: [AIPage.Attachment] = []
        if chat.attachPage, let page = chipPage {
            out.append(AIPage.Attachment(kind: .page,
                                         title: page.title.isEmpty ? (page.pageAddress?.host() ?? "") : page.title,
                                         detail: page.pageAddress?.host() ?? ""))
        }
        return out + chat.extras
    }

    /// A row that scrolls sideways once there are more chips than fit: three
    /// of them in a 380-point column would otherwise be squeezed to nothing.
    @ViewBuilder private var chipRow: some View {
        if drawn {
            row
        } else {
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                chipView(chip)
            }
            Spacer(minLength: 0)
        }
    }

    private func chipView(_ attachment: AIPage.Attachment) -> some View {
        HStack(spacing: 8) {
            Group {
                if attachment.kind == .page || attachment.kind == .tab,
                   let icon = attachment.read?.url.flatMap({ Favicons.shared.cached(for: $0) }) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                } else {
                    Image(systemName: attachment.kind.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.Chat.muted)
                        .frame(width: 16, height: 16)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: attachment.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.Chat.ink)
                    .lineLimit(1)
                Text(verbatim: attachment.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.Chat.muted)
                    .lineLimit(1)
            }
            Button {
                take(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.Chat.faint)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Localized("Take This Off"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: 230)
        .background(Palette.Chat.ink.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The cross on a chip: the page comes off this question, an added tab, a
    /// file or a picture is dropped.
    private func take(_ attachment: AIPage.Attachment) {
        if attachment.kind == .page {
            chat.attachPage = false
        } else {
            chat.extras.removeAll { $0.id == attachment.id }
        }
    }

    @ViewBuilder private var addItems: some View {
        if !chat.attachPage, let page = chipPage {
            Button(Localized("This Page")) {
                chat.attachPage = true
                _ = page
            }
        }
        if !otherTabs.isEmpty {
            Section(Localized("Tabs")) {
                ForEach(otherTabs) { tab in
                    Button(tab.title.isEmpty ? (tab.pageAddress?.host() ?? Localized("Tab")) : tab.title) {
                        attach(tab)
                    }
                }
            }
        }
        Button(Localized("Choose a File…")) { chooseFile() }
        Button(Localized("Screenshot This Page")) { shot() }
    }

    /// The tabs that can be added: web pages, this one aside, a handful.
    private var otherTabs: [Tab] {
        let here = chipPage?.id
        return Array(browser.tabs.filter { $0.isWeb && $0.id != here }.prefix(8))
    }

    private func attach(_ tab: Tab) {
        Task { @MainActor in
            guard let read = await AIPage.read(tab, source: "tab") else {
                browser.announce(Localized("There's nothing on that page to read."))
                return
            }
            chat.extras.append(AIPage.Attachment(kind: .tab,
                                                 title: read.title.isEmpty ? (tab.pageAddress?.host() ?? Localized("Tab")) : read.title,
                                                 detail: tab.pageAddress?.host() ?? "",
                                                 read: read))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = Localized("A file to ask about: text, or a PDF")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let read = AIPage.readFile(url) else {
                browser.announce(Localized("\(url.lastPathComponent) can't be read as text"))
                continue
            }
            chat.extras.append(AIPage.Attachment(kind: .file,
                                                 title: url.lastPathComponent,
                                                 detail: url.deletingLastPathComponent().lastPathComponent,
                                                 read: read))
        }
    }

    /// A picture of the page, for a model that can look at one.
    private func shot() {
        guard let tab = chipPage else {
            browser.announce(Localized("Open a page to take a picture of it"))
            return
        }
        Task { @MainActor in
            guard let image = await AIPage.shot(tab) else {
                browser.announce(Localized("That page can't be pictured"))
                return
            }
            chat.extras.append(AIPage.Attachment(kind: .shot,
                                                 title: Localized("Screenshot"),
                                                 detail: tab.pageAddress?.host() ?? "",
                                                 image: image))
        }
    }

    private var chipPage: Tab? {
        guard let tab = browser.active, tab.isWeb else { return nil }
        return tab
    }

    private func setupCard(_ setup: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: setup)
                .font(.system(size: 13))
                .foregroundStyle(Palette.Chat.muted)
                .fixedSize(horizontal: false, vertical: true)
            Pill("Open Settings › AI") {
                browser.settingsPage = .ai
                browser.tuning = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.Chat.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func noticeCard(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Localized("Answers from \(chat.provider.name)"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.Chat.ink)
            Text(verbatim: notice)
                .font(.system(size: 13))
                .foregroundStyle(Palette.Chat.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Pill("Cancel") { chat.disagree() }
                Pill("Agree", filled: true) { chat.agree() }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.Chat.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Nothing to read: said where it happened, and gone with the next
    /// question.
    private func troubleCard(_ trouble: String) -> some View {
        Text(verbatim: trouble)
            .font(.system(size: 13))
            .foregroundStyle(Palette.Chat.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.Chat.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var ready: Bool { !chat.draft.trimmed.isEmpty || chat.busy }

    private func send() {
        if browser.chatSetup != nil {
            browser.settingsPage = .ai
            browser.tuning = true
            return
        }
        chat.submit(from: browser.active)
    }
}

// MARK: - the column beside the page

/// The conversation in the column beside the page (see SidePanel.swift): what
/// its head says, then the writing with the field floating over its foot.
struct ChatPane: View {
    @ObservedObject var browser: Browser
    @ObservedObject var chat: Chat
    /// Drawn off screen, for a picture (bench ai picture).
    var drawn = false

    @Environment(\.colorScheme) private var scheme

    /// The column is narrower than a page: the writing keeps its margins and
    /// gives up being 760 wide.
    private var column: CGFloat { drawn ? 660 : 720 }

    var body: some View {
        VStack(spacing: 0) {
            head
            ZStack(alignment: .bottom) {
                ChatThread(chat: chat, seed: seed, pageOpen: browser.active?.isWeb == true,
                           drawn: drawn, column: column, foot: 150)
                ChatComposer(browser: browser, chat: chat, column: column, drawn: drawn)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
        }
        .background(Palette.Chat.raised)
    }

    /// What this is and the doors out of it: another conversation, the same
    /// one as a page, and away.
    private var head: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.Chat.faint)
            Text(chat.title.isEmpty ? Localized("Chat") : chat.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.Chat.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Door(icon: "plus", help: Localized("New Chat")) { browser.newChat() }
            Door(icon: "arrow.up.left.and.arrow.down.right", help: Localized("Open as a Page")) { browser.expandChat() }
            Door(icon: "xmark", help: Localized("Close   esc")) { browser.closeChat() }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Palette.Chat.raised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.Chat.edge).frame(height: 0.5)
        }
    }

    private var seed: Color {
        guard browser.prefs.usesSpaces else { return Palette.Chat.muted }
        return Color(nsColor: SpacePalette.title(browser.space.spaceTheme, dark: scheme == .dark))
    }
}

// MARK: - the answer, set

/// What the answer says, set the way a letter is set: headings heavier than
/// the rest, bullets given their own indent, a quote ruled down its left.
/// A small reader for the little markdown a model writes — nothing is
/// fetched, nothing is linked, and a line it doesn't recognise is set as
/// plain text.
struct Wrote: View {
    let text: String

    init(_ text: String) { self.text = text }

    private struct Line: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case body, big, medium, small, bullet, quote, code }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines) { line in
                switch line.kind {
                case .big, .medium, .small:
                    Text(verbatim: line.text)
                        .font(.system(size: line.kind == .big ? 20 : line.kind == .medium ? 17 : 15,
                                      weight: .semibold))
                        .foregroundStyle(Palette.Chat.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•").font(.system(size: 15)).foregroundStyle(Palette.Chat.ink)
                        Text(verbatim: line.text)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.Chat.ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 6)
                case .quote:
                    HStack(alignment: .top, spacing: 12) {
                        Rectangle()
                            .fill(Palette.Chat.ink.opacity(0.18))
                            .frame(width: 3)
                        Text(verbatim: line.text)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.Chat.muted)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .code:
                    Text(verbatim: line.text)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Palette.Chat.ink)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.Chat.ink.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .body:
                    Text(verbatim: line.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.Chat.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// The answer cut into the lines it was written as. Consecutive plain
    /// lines join, since a model wraps a paragraph over several of them.
    private var lines: [Line] {
        var out: [Line] = []
        var paragraph: [String] = []
        var fenced = false
        var code: [String] = []
        func flush() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { out.append(Line(text: joined, kind: .body)) }
            paragraph = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if fenced {
                    out.append(Line(text: code.joined(separator: "\n"), kind: .code))
                    code = []
                } else {
                    flush()
                }
                fenced.toggle()
                continue
            }
            if fenced { code.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("###") { flush(); out.append(Line(text: plain(line), kind: .small)); continue }
            if line.hasPrefix("##") { flush(); out.append(Line(text: plain(line), kind: .medium)); continue }
            if line.hasPrefix("#") { flush(); out.append(Line(text: plain(line), kind: .big)); continue }
            if line.hasPrefix("> ") { flush(); out.append(Line(text: String(line.dropFirst(2)), kind: .quote)); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush(); out.append(Line(text: String(line.dropFirst(2)), kind: .bullet)); continue
            }
            paragraph.append(line)
        }
        flush()
        if !code.isEmpty { out.append(Line(text: code.joined(separator: "\n"), kind: .code)) }
        return out
    }

    private func plain(_ line: String) -> String {
        line.drop { $0 == "#" || $0 == " " }.description
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
