import SwiftUI

// The conversation as a place of its own, beside nothing: Dia's chat fills
// the page's own area rather than sitting in a card on the right — a head
// line where the page's toolbar is, a column of writing, and the field
// floating over the foot of it.
//
// What is Dia's here, read off the application:
//   · the head says where you are — a bubble, "Chat", then the first thing
//     you asked — with back, forward and reload in front of it;
//   · the answer is written, not boxed: 15 points on the page's white, its
//     headings heavier, its bullets indented, a quote ruled down the left;
//   · what you asked is a bubble tinted with the space's colour, 17 round,
//     set to the right;
//   · a sphere breathes while it thinks;
//   · the field is one floating pill near the bottom: what you type, then
//     small doors — a plus, a microphone — and the filled circle to send.
// Everything else — the ring, the inks, the ring round the field — is the
// browser's own.

struct ChatPane: View {
    @ObservedObject var browser: Browser
    @ObservedObject var chat: Chat
    /// Drawn off screen, for a picture (bench ai picture): the scroll view
    /// and the field stood in for, as the page's panel does.
    var drawn = false

    @Environment(\.colorScheme) private var scheme
    @FocusState private var typing: Bool

    /// The column of writing: wide enough for a paragraph, never the whole
    /// window.
    private static let column: CGFloat = 760

    var body: some View {
        VStack(spacing: 0) {
            head
            ZStack(alignment: .bottom) {
                paper
                field.padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(Palette.Chat.raised)
        .onAppear { typing = true }
    }

    // MARK: - the head line

    private var head: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                navDoor("chevron.left", help: "Back   ⌘[", on: browser.active?.canGoBack ?? false) { browser.back() }
                navDoor("chevron.right", help: "Forward   ⌘]", on: browser.active?.canGoForward ?? false) { browser.forward() }
                navDoor("arrow.clockwise", help: "Reload   ⌘R", on: browser.active?.isWeb ?? false) { browser.reload() }
            }
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.Chat.faint)
                Text("Chat")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.Chat.muted)
                if let first = chat.lines.first(where: { $0.mine })?.text ?? nil {
                    Text(verbatim: "/").font(.system(size: 13)).foregroundStyle(Palette.Chat.faint)
                    Text(first.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.Chat.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func navDoor(_ icon: String, help: String, on: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Palette.Chat.muted : Palette.Chat.faint.opacity(0.5))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .help(help)
    }

    // MARK: - the writing

    @ViewBuilder private var paper: some View {
        if drawn {
            column
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 150)
        } else {
            ScrollViewReader { scroller in
                ScrollView {
                    column
                        .frame(maxWidth: Self.column, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 140)
                    Color.clear.frame(height: 1).id("foot")
                }
                .onChange(of: chat.lines.count) { _, _ in scroll(scroller) }
                .onChange(of: chat.lines.last?.text) { _, _ in scroll(scroller) }
            }
        }
    }

    @ViewBuilder private var column: some View {
        if chat.empty {
            empty
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(chat.lines) { line in row(line) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func row(_ line: Chat.Line) -> some View {
        if line.mine {
            HStack(spacing: 0) {
                Spacer(minLength: 120)
                Text(line.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.Chat.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(LinearGradient(colors: [tint(0.12), tint(0.09)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
            }
        } else if line.text.isEmpty, !line.done {
            HStack(spacing: 10) {
                Orb(seed: seed, size: 24)
                Text(chat.reading ? "Reading this page…" : "Thinking…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.Chat.faint)
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Wrote(line.text)
                if let failed = line.failed {
                    Text(failed.localized)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.Chat.faint)
                } else if line.done {
                    marks(line)
                }
            }
        }
    }

    /// What is under an answer in Dia: the thumb that liked it, the one that
    /// didn't, and the copy.
    private func marks(_ line: Chat.Line) -> some View {
        HStack(spacing: 16) {
            markDoor("hand.thumbsup") { }
            markDoor("hand.thumbsdown") { }
            markDoor("square.on.square") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.text, forType: .string)
            }
            Text(line.at.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(Palette.Chat.faint)
            Text(chat.place)
                .font(.system(size: 11))
                .foregroundStyle(Palette.Chat.faint)
                .lineLimit(1)
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

    /// Nothing asked yet: the tip card Dia opens with, then the two lines.
    private var empty: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "camera")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.Chat.ink)
                    Text("Capture Tool")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.Chat.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Palette.Chat.ink.opacity(0.06))

                VStack(alignment: .leading, spacing: 6) {
                    Text("What's this page about?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.Chat.ink)
                    Text("Or anything you're looking at.")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.Chat.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Palette.Chat.raised)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.Chat.edge, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .frame(maxWidth: 360)
            .padding(.horizontal, 20)

            VStack(spacing: 8) {
                Text("Ask about something you see")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.Chat.ink)
                Text(browser.active?.isWeb == true
                     ? "Aura reads the page you're on, and nothing is sent until you ask"
                     : "Open a page and Aura can read it with your question")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.Chat.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - the field

    @ViewBuilder private var field: some View {
        VStack(spacing: 8) {
            if let setup = browser.chatSetup {
                setupCard(setup)
            } else if let notice = chat.notice {
                noticeCard(notice)
            } else {
                pill
            }
        }
        .frame(maxWidth: Self.column)
    }

    /// One floating pill: what you type, a plus, the microphone, the send.
    private var pill: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let page = chipPage {
                pageChip(page)
            }
            HStack(alignment: .bottom, spacing: 12) {
                if drawn {
                    Text("Ask another question…")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.Chat.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: $chat.draft,
                              prompt: Text("Ask another question…").foregroundStyle(Palette.Chat.faint),
                              axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.Chat.ink)
                        .lineLimit(1...6)
                        .focused($typing)
                        .onSubmit { send() }
                        .disabled(chat.busy)
                }
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.Chat.faint)
                Image(systemName: "mic")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.Chat.faint)
                Button {
                    if chat.busy { chat.stop() } else { send() }
                } label: {
                    Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.Chat.raised)
                        .frame(width: 30, height: 30)
                        .background(ready ? Palette.Chat.ink : Palette.Chat.faint, in: Circle())
                }
                .buttonStyle(.plain)
                .help(chat.busy ? "Stop" : "Send   ⏎")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.Chat.raised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Palette.Chat.edge, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }

    private func pageChip(_ page: Tab) -> some View {
        HStack(spacing: 10) {
            Mark(icon: Favicons.shared.cached(for: page.pageAddress),
                 letter: String(((page.pageAddress?.host() ?? "•").prefix(1))).uppercased(), size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? (page.pageAddress?.host() ?? "") : page.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.Chat.ink)
                    .lineLimit(1)
                Text(page.pageAddress?.host() ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.Chat.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.Chat.ink.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chipPage: Tab? {
        guard let tab = browser.active, tab.isWeb else { return nil }
        return tab
    }

    private func setupCard(_ setup: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(setup.localized)
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
            Text(notice.localized)
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

    // MARK: - sending

    private var ready: Bool { !chat.draft.trimmed.isEmpty || chat.busy }

    private func send() {
        if browser.chatSetup != nil {
            browser.settingsPage = .ai
            browser.tuning = true
            return
        }
        chat.submit(from: browser.active)
    }

    // MARK: - the space's own colour

    private var seed: Color {
        guard browser.prefs.usesSpaces else { return Palette.Chat.muted }
        return Color(nsColor: SpacePalette.title(browser.space.spaceTheme, dark: scheme == .dark))
    }

    private func tint(_ amount: Double) -> Color { seed.opacity(amount) }

    private func scroll(_ scroller: ScrollViewProxy) {
        withAnimation(Motion.quick) { scroller.scrollTo("foot", anchor: .bottom) }
    }
}

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
