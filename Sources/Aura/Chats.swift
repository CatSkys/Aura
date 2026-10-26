import Combine
import Foundation

// The conversations as a library: Dia's own shape, read off the application
// (BoostBrowser/Sources/DiaLibrary — ChatsDataSource, LibrarySurface,
// LibraryDock, and ChatHistoryPanel's Recents) reduced to what Aura has. Dia
// keeps one list and shows it twice, beside the page and on a page of its
// own; there are no artifacts, shares or accounts here, so this is the list
// and nothing else.
//
// A profile keeps its own (Profiles.chats), and a window reads that one: the
// column beside a page and the page of its own (search://chat) show the same
// conversations, and the one in front is the window's (Browser.chat).
//
// Kept in chats.json, and only while Settings › AI › Keep chats is on:
// turned off, nothing is written and a conversation dies with the window, as
// it did before there was a list. What is written down is what you asked,
// what was answered and where it ran — never the page's own text, which went
// to the model once and stays out of this file. A conversation opened again
// after a while answers as one whose pages it can no longer quote: the
// questions and the answers are there, the pages that went with them are
// not.

@MainActor
final class Chats: ObservableObject {
    /// Every conversation this profile has, in the order they were made.
    @Published private(set) var list: [Chat] = []
    /// What is typed in the page's search field.
    @Published var hunt = ""

    private let fileName: String
    /// Its profile deleted: nothing more is written.
    private var retired = false
    /// One per conversation, so a saved one is written again when it changes
    /// — after the answer has settled, not on every piece of it.
    private var watchdogs: [UUID: AnyCancellable] = [:]
    private var pending: DispatchWorkItem?

    init(file: String = "chats.json") {
        fileName = file
        load()
    }

    private var file: URL { Store.file(fileName) }

    /// Whether a conversation is written down at all: Settings › AI › Keep
    /// chats, on unless it was turned off. Read without the actor, since a
    /// notice about what a provider is sent says it too (AIAssist.notice).
    nonisolated static var keeps: Bool { Store.settings.object(forKey: "ai.keep") as? Bool ?? true }

    /// Newest first, and only what the search fits: a title, or anything
    /// said in it.
    var shown: [Chat] {
        let words = hunt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = list.sorted { $0.updated > $1.updated }
        guard !words.isEmpty else { return all }
        return all.filter { chat in
            chat.title.lowercased().contains(words)
                || chat.lines.contains { $0.text.lowercased().contains(words) }
        }
    }

    func open(_ id: Chat.ID) -> Chat? { list.first { $0.id == id } }

    /// The one last talked in: what the column opens on, and what the page
    /// shows before you have chosen.
    var newest: Chat? { list.max { $0.updated < $1.updated } }

    @discardableResult
    func make(provider: AIProvider, model: String) -> Chat {
        let chat = Chat(provider: provider, model: model)
        adopt(chat)
        return chat
    }

    func adopt(_ chat: Chat) {
        list.append(chat)
        watch(chat)
        saveSoon()
    }

    func rename(_ chat: Chat, to name: String) {
        chat.rename(name)
        saveSoon()
    }

    func forget(_ chat: Chat) {
        chat.stop()
        watchdogs[chat.id] = nil
        list.removeAll { $0.id == chat.id }
        saveSoon()
    }

    func clear() {
        list.forEach { $0.stop() }
        watchdogs = [:]
        pending?.cancel()
        list = []
        save()
    }

    /// Its profile deleted: emptied, its file removed, nothing written again.
    func retire() {
        retired = true
        pending?.cancel()
        watchdogs = [:]
        list = []
        Disk.remove(file)
    }

    // MARK: - the file

    private func load() {
        // Off, and nothing written down is read either: the file goes when
        // the switch does (see save), and a copy left over from before it was
        // turned off is not this window's business.
        guard Chats.keeps else { return }
        guard let data = try? Data(contentsOf: file),
              let records = try? JSONDecoder().decode([Chat.Record].self, from: data)
        else { return }
        // A conversation that says nothing is not worth a row.
        list = records.filter { !$0.lines.isEmpty }.map(Chat.init(record:))
        list.forEach(watch)
    }

    private func watch(_ chat: Chat) {
        watchdogs[chat.id] = chat.objectWillChange
            .sink { [weak self] in self?.saveSoon() }
    }

    /// A second or so after the last change: a conversation being written out
    /// piece by piece is not written to disk piece by piece.
    private func saveSoon() {
        guard !retired, Chats.keeps else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Now, for anything that ends — a profile going, the page cleared, the
    /// switch turned off, which takes the file with it.
    func save() {
        guard !retired else { return }
        guard Chats.keeps else { Disk.remove(file); return }
        let records = list.map(\.record)
        Disk.write(file) { try? JSONEncoder().encode(records) }
    }

    /// For the way out: what changed is on disk before the process ends.
    func saveNow() {
        pending?.cancel()
        save()
        Disk.drain()
    }
}
