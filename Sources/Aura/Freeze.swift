import WebKit

// A page put aside rather than thrown away.
//
// Sleeping a tab has always meant letting go of its view, and a page let go
// of comes back by loading: on the sites people keep open all day that is a
// second or three of the page booting again, which is the difference between
// a tab that was asleep and a tab that was closed. WebKit has a second way of
// putting a page down — the one it takes into the back-forward cache — where
// the page is set aside whole: the document, its JavaScript heap, what was
// typed into it, where it was scrolled to, its back list. Given back, all of
// that is there at once and nothing is fetched.
//
// The two calls that do it are outside the public framework (macOS 12 and
// later), so each is asked for by name first and a WebKit without them is
// left alone, the way `Muter` asks for its own. They are the pair WebKit's
// own tab-sleeping is built on: the Bugzilla entry that added them says as
// much, and says the other thing worth knowing here — that a page set aside
// may only be given back, or have its view destroyed. Anything else done to
// one raises, which is why the tab keeps it where no other code can reach it
// while it sleeps (see `Tab.frozen`).
//
// What this costs is nothing when it happens and the page's own memory while
// it lasts, so only a few pages are kept (`budget`), the rest sleep the old
// way, and memory pressure lets the kept ones go first. That is the order
// Chrome keeps its tabs in: freeze, and discard only when the memory is
// needed.

enum Freeze {
    /// How many pages are kept aside at once. Five is the row of tabs most
    /// people move between in an afternoon; past that, the memory a page
    /// holds — a hundred to three hundred megabytes — is worth more than the
    /// second it saves, and the tab sleeps the old way.
    static let budget = 5

    /// Whether this Mac's WebKit has the two calls at all.
    static func available(_ web: WKWebView) -> Bool {
        web.responds(to: NSSelectorFromString(suspending)) && web.responds(to: NSSelectorFromString(waking))
    }

    /// The page set aside: its DOM and its JavaScript kept, its timers and
    /// its drawing stopped. Answers false where this WebKit can't, in which
    /// case nothing has been done to the page and it is let go of the old way
    /// instead.
    @discardableResult
    static func suspend(_ web: WKWebView, then done: ((Bool) -> Void)? = nil) -> Bool {
        guard let method = method(web, suspending) else { return false }
        method(web, NSSelectorFromString(suspending)) { ok in done?(ok) }
        return true
    }

    /// The page back, as it was. Told false when WebKit has nothing to give
    /// back — the page was pruned under memory pressure, or its process went
    /// while it was aside — and the tab loads it instead.
    static func resume(_ web: WKWebView, then done: @escaping (Bool) -> Void) {
        guard let method = method(web, waking) else { return done(false) }
        method(web, NSSelectorFromString(waking)) { ok in done(ok) }
    }

    private static let suspending = "_suspendPage:"
    private static let waking = "_resumePage:"

    /// Either call, as the C function behind its selector — nil where this
    /// WebKit doesn't have it. `unsafeBitCast` rather than `perform(_:with:)`
    /// because a block argument isn't something `perform` carries; the name
    /// is asked for first, so the cast is only ever made on a method that is
    /// there.
    private static func method(
        _ web: WKWebView, _ name: String
    ) -> (@convention(c) (AnyObject, Selector, @escaping @convention(block) (Bool) -> Void) -> Void)? {
        let selector = NSSelectorFromString(name)
        guard web.responds(to: selector) else { return nil }
        typealias Call = @convention(c) (AnyObject, Selector, @escaping @convention(block) (Bool) -> Void) -> Void
        return unsafeBitCast(web.method(for: selector), to: Call.self)
    }
}
