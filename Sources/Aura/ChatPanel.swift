import SwiftUI

// The conversation's panel, beside the page: Dia's, rebuilt in AppKit's own
// grammar. What makes it read as Dia is not the colours alone —
//   · what you wrote sits in a bubble tinted with the space's own colour,
//     top to bottom, 17 points round;
//   · what the answer says has no bubble at all: 15 points of plain text on
//     the panel's surface, the way a letter is plain;
//   · while it is working, a sphere breathes where the answer will be;
//   · the field you type in is a raised white capsule with the send button
//     inside its right end, and one line under it says where the answer came
//     from.
// Everything else here — the header, the ring round the card — is the
// browser's own, so the panel does not come from another application.

struct ChatPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var chat: Chat
    /// The page as a card, and so this one.
    var card = true
    /// Drawn off screen, for a picture (bench ai picture): what an image
    /// renderer can't draw — a scroll view, a field — stood in for, as the
    /// page's panel does (AssistantPanel.drawn).
    var drawn = false

    @Environment(\.colorScheme) private var scheme
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.Chat.edge)
            conversation
            foot
        }
        .background(Palette.Chat.surface)
        .modifier(CardEdge(on: card))
        .onAppear { typing = true }
    }

    // MARK: - head

    private var header: some View {
        HStack(spacing: 8) {
            Text("Chat")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.Chat.ink)
            Spacer(minLength: 0)
            Button {
                browser.closeChat()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.Chat.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close   esc")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
    }

    // MARK: - what has been said

    @ViewBuilder private var conversation: some View {
        if drawn {
            said.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
        } else {
            scrolling
        }
    }

    private var said: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if chat.empty { empty }
            ForEach(chat.lines) { line in
                row(line)
            }
        }
    }

    private var scrolling: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if chat.empty { empty }
                    ForEach(chat.lines) { line in
                        row(line)
                    }
                    Color.clear.frame(height: 1).id("foot")
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .onChange(of: chat.lines.count) { _, _ in scroll(scroller) }
            .onChange(of: chat.lines.last?.text) { _, _ in scroll(scroller) }
        }
    }

    @ViewBuilder private func row(_ line: Chat.Line) -> some View {
        if line.mine {
            HStack(spacing: 0) {
                Spacer(minLength: 48)
                Text(line.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.Chat.ink)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint(0.12), tint(0.09)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
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
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(line.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.Chat.ink)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let failed = line.failed {
                    Text(failed.localized)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.Chat.faint)
                } else if line.done {
                    Text(footnote(line))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.Chat.faint)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Orb(seed: seed, size: 24, moving: false)
            Text("Ask about this page, or anything else.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.Chat.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let page = browser.active?.title, let host = browser.active?.pageAddress?.host {
                Text(Localized("Reading \(host) · \(page)"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.Chat.faint)
                    .lineLimit(2)
            }
        }
        .padding(.top, 6)
    }

    private func footnote(_ line: Chat.Line) -> String {
        let time = line.at.formatted(date: .omitted, time: .shortened)
        return "\(time) · \(chat.place)"
    }

    // MARK: - what goes under it

    @ViewBuilder private var foot: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let setup = browser.chatSetup {
                VStack(alignment: .leading, spacing: 10) {
                    Text(setup.localized)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.Chat.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Pill("Open Settings › AI") {
                        browser.settingsPage = .ai
                        browser.tuning = true
                    }
                }
                .padding(12)
                .background(Palette.Chat.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let notice = chat.notice {
                VStack(alignment: .leading, spacing: 10) {
                    Text(notice.localized)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.Chat.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Pill("Cancel") { chat.disagree() }
                        Pill("Agree", filled: true) { chat.agree() }
                        Spacer(minLength: 0)
                    }
                }
                .padding(12)
                .background(Palette.Chat.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                composer
            }
            Text("AI — may be wrong")
                .font(.system(size: 11))
                .foregroundStyle(Palette.Chat.faint)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if drawn {
                Text("Ask anything…")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.Chat.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $chat.draft, prompt: Text("Ask anything…").foregroundStyle(Palette.Chat.faint))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.Chat.ink)
                    .focused($typing)
                    .onSubmit {
                        if browser.chatSetup != nil { browser.settingsPage = .ai; browser.tuning = true }
                        else { chat.submit(from: browser.active) }
                    }
                    .disabled(chat.busy)
            }
            Button {
                if chat.busy { chat.stop() } else { chat.submit(from: browser.active) }
            } label: {
                Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.Chat.raised)
                    .frame(width: 22, height: 22)
                    .background(chat.draft.trimmed.isEmpty && !chat.busy
                                ? Palette.Chat.faint : Palette.Chat.ink,
                                in: Capsule())
            }
            .buttonStyle(.plain)
            .help(chat.busy ? "Stop" : "Send   ⏎")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Palette.Chat.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.Chat.edge, lineWidth: 0.5)
        }
    }

    // MARK: - the space's own colour

    /// The space's title colour, which is what the bubble and the sphere are
    /// tinted with — a neutral where spaces are off.
    private var seed: Color {
        guard browser.prefs.usesSpaces else { return Palette.Chat.muted }
        return Color(nsColor: SpacePalette.title(browser.space.spaceTheme, dark: scheme == .dark))
    }

    private func tint(_ amount: Double) -> Color { seed.opacity(amount) }

    private func scroll(_ scroller: ScrollViewProxy) {
        withAnimation(Motion.quick) { scroller.scrollTo("foot", anchor: .bottom) }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The conversation filling the card the window gives the column beside the
/// page — the same shape the side panel takes (see SidePanelBeside), so the
/// two are one column traded between them rather than two layouts.
struct ChatBeside: View {
    @ObservedObject var browser: Browser
    @ObservedObject var chat: Chat
    /// On the left of the page, the column being on its right.
    let onLeft: Bool
    /// The page as a card, and so this one.
    let card: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if !onLeft { edge }
            ChatPanel(browser: browser, chat: chat, card: card)
                .frame(width: width)
            if onLeft { edge }
        }
    }

    /// The card's gap, or the hairline: whichever the window is drawing.
    @ViewBuilder private var edge: some View {
        if card {
            Color.clear.frame(width: Metrics.cardGap)
        } else {
            Rectangle().fill(Palette.hairline).frame(width: 1)
        }
    }
}
