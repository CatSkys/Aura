import AppKit

// The two questions the assistant can put to you: one it asks itself (a
// confirmation before something that can't be taken back, AIToolRisk), and one
// the model asks through its `ask_user` tool.
//
// Both are sheets on the window, drawn the way the capture card and the
// space's own questions are — an NSAlert, the same shape the rest of the
// browser asks things in, because a browser's own question should look like
// the browser's and not like a web page's.
//
// Both take no clicks in their first half second. That rule is CaptureAsk's
// (Browser.swift): a page can time a click to land where a button is about to
// be, and this is the one place where that trick would press "Allow".
//
// A test run answers without a sheet, the way Ask.testing does, so a probe can
// drive the loop without a window that a hidden run can't show.

@MainActor
enum AIToolAsk {
    /// What a confirmation may be answered.
    enum Confirm: Equatable {
        case allow
        /// Allowed, and remembered for this site and this class of action.
        case always
        case refuse
    }

    /// What `ask_user` may be answered.
    enum Answer: Equatable {
        /// Done: the person says they are ready to go on.
        case done
        /// They stopped the whole thing.
        case stop
        /// They closed it without answering.
        case cancel
    }

    /// A test run's answer to a confirmation, in place of a sheet. Never set
    /// otherwise.
    static var confirming: Confirm?
    /// A test run's answer to `ask_user`.
    static var answering: Answer?

    /// Whether the person may be asked anything at all. Off in a window that
    /// has gone, where a sheet would hang on nothing.
    private static func window(_ browser: Browser) -> NSWindow? { browser.window ?? Links.window }

    // MARK: - may this happen

    /// The confirmation card for something that can't be taken back.
    static func confirm(kind: AIToolRisk.Class, what: String, site: String, in browser: Browser) async -> Confirm {
        if Store.testing, let answer = confirming { return answer }
        let alert = NSAlert()
        alert.messageText = kind.title
        alert.informativeText = kind.detail(what, site.isEmpty ? Localized("this page") : site)
        alert.alertStyle = .warning
        alert.addButton(withTitle: Localized("Yes, Once"))
        // A payment is never remembered, so it is offered no such button.
        if kind.remembers { alert.addButton(withTitle: Localized("Always on This Site")) }
        alert.addButton(withTitle: Localized("No"))
        let shown = Date()
        let answer = await sheet(alert, in: browser)
        // A click in the first half second is a page's, not yours.
        if Date().timeIntervalSince(shown) < 0.5 { return .refuse }
        if answer == .alertFirstButtonReturn { return .allow }
        if kind.remembers, answer == .alertSecondButtonReturn { return .always }
        return .refuse
    }

    // MARK: - the model's own question

    /// `ask_user`: the model stops and hands the page back to you — a sign-in,
    /// a code, a password, a decision. Nothing is filled in for you.
    static func ask(title: String, reason: String, in browser: Browser) async -> Answer {
        if Store.testing, let answer = answering { return answer }
        let alert = NSAlert()
        alert.messageText = title.isEmpty ? Localized("The assistant needs you") : title
        alert.informativeText = reason
        alert.addButton(withTitle: Localized("Done, Go On"))
        alert.addButton(withTitle: Localized("Stop Here"))
        let shown = Date()
        let answer = await sheet(alert, in: browser)
        if Date().timeIntervalSince(shown) < 0.5 { return .cancel }
        return answer == .alertFirstButtonReturn ? .done : .stop
    }

    // MARK: - a sheet

    private static func sheet(_ alert: NSAlert, in browser: Browser) async -> NSApplication.ModalResponse {
        guard let window = window(browser) else { return .cancel }
        return await withCheckedContinuation { done in
            alert.beginSheetModal(for: window) { done.resume(returning: $0) }
        }
    }
}
