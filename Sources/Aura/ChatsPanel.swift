import SwiftUI

// The conversations as a page of their own: `search://chat`, in a tab like
// Settings and History (InternalPages.swift), as Dia's library has a surface
// of its own beside the panel it also lives in (DiaLibrary's
// LibrarySurfaceViewController: a search field, sections, a row's own
// actions). The column down the left is every conversation this profile
// keeps — newest first, by day — and the rest of the page is the one in
// front: the same writing and the same field the column beside a page shows.
//
// What a row does: a click opens it, the pencil renames it in place, the bin
// forgets it. The foot counts them and offers to clear the lot, with the one
// question a clear-all deserves in between.

struct ChatsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var chats: Chats

    /// Drawn off screen, for a picture (bench ai picture): the scroll views
    /// stood in for, as the column's are.
    var drawn = false

    @Environment(\.colorScheme) private var scheme
    @State private var renaming: Chat.ID?
    @State private var draftName = ""
    @State private var over: Chat.ID?
    @State private var clearing = false
    @FocusState private var hunting: Bool
    @FocusState private var naming: Bool

    /// Wide enough for a title and a time, narrow enough to leave the writing
    /// the page.
    private static let rail: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Palette.hairline).frame(width: 1)
            thread
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        // Nothing chosen yet: the one last talked in, as the column opens on.
        .onAppear { if browser.chat == nil { browser.chat = chats.newest } }
    }

    // MARK: - the column of conversations

    private var rail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Chats")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Door(icon: "plus", help: Localized("New Chat")) { newChat() }
            }
            .padding(.top, 44)

            Hunt(text: $chats.hunt, prompt: Localized("Search chats"), focus: $hunting)

            if chats.shown.isEmpty {
                Text(chats.hunt.isEmpty ? Localized("No conversations yet.") : Localized("Nothing matches."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 2)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else if drawn {
                list.padding(.bottom, 8)
            } else {
                ScrollView(showsIndicators: false) {
                    list.padding(.bottom, 8)
                }
            }

            foot
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(width: Self.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.day) { group in
                Caption(group.day)
                    .padding(.top, group.day == groups.first?.day ? 2 : 14)
                    .padding(.bottom, 4)
                    .padding(.leading, 2)
                ForEach(group.chats) { chat in row(chat) }
            }
        }
    }

    /// Newest first, cut into the days they were last used: Dia's Recents, as
    /// History's own list is cut into days.
    private var groups: [(day: String, chats: [Chat])] {
        var out: [(String, [Chat])] = []
        for chat in chats.shown {
            let day = When.day(chat.updated)
            if let last = out.last, last.0 == day {
                out[out.count - 1].1.append(chat)
            } else {
                out.append((day, [chat]))
            }
        }
        return out
    }

    private func row(_ chat: Chat) -> some View {
        let chosen = browser.chat?.id == chat.id
        return HStack(spacing: 6) {
            if renaming == chat.id {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .focused($naming)
                    .onSubmit { commit(chat) }
                    .onExitCommand { renaming = nil }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title.isEmpty ? Localized("New Chat") : chat.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(When.said(chat.updated))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if over == chat.id || chosen {
                    Door(icon: "pencil", help: Localized("Rename")) { begin(chat) }
                    Door(icon: "trash", help: Localized("Forget This Chat")) { forget(chat) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chosen ? Palette.ink.opacity(0.05) : (over == chat.id ? Palette.ink.opacity(0.03) : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { if renaming != chat.id { open(chat) } }
        .onHover { inside in
            if inside { over = chat.id } else if over == chat.id { over = nil }
        }
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            if clearing {
                Text(Localized("Forget every conversation? The pages they were about are not affected."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Pill("Forget Them", filled: true) {
                        chats.clear()
                        browser.chat = nil
                        clearing = false
                    }
                    Pill("Cancel") { clearing = false }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    Text(chats.shown.count == 1 ? Localized("1 conversation") : Localized("\(chats.shown.count) conversations"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    if !chats.list.isEmpty { Pill("Forget All…") { clearing = true } }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - the conversation in front

    @ViewBuilder private var thread: some View {
        if let chat = browser.chat {
            ZStack(alignment: .bottom) {
                ChatThread(chat: chat, seed: seed, pageOpen: browser.active?.isWeb == true,
                           drawn: drawn, column: 760, foot: 132)
                    .id(chat.id)
                ChatComposer(browser: browser, chat: chat, column: 760)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.Chat.raised)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.muted)
                Text("Nothing open")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Choose a conversation, or start one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                Pill("New Chat", filled: true) { newChat() }
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.Chat.raised)
        }
    }

    private var seed: Color {
        guard browser.prefs.usesSpaces else { return Palette.Chat.muted }
        return Color(nsColor: SpacePalette.title(browser.space.spaceTheme, dark: scheme == .dark))
    }

    // MARK: - what a row does

    private func open(_ chat: Chat) {
        browser.chat = chat
    }

    private func newChat() {
        browser.newChat()
    }

    private func begin(_ chat: Chat) {
        draftName = chat.title
        renaming = chat.id
        naming = true
    }

    private func commit(_ chat: Chat) {
        chats.rename(chat, to: draftName)
        renaming = nil
    }

    private func forget(_ chat: Chat) {
        if browser.chat?.id == chat.id { browser.chat = nil }
        chats.forget(chat)
    }
}
