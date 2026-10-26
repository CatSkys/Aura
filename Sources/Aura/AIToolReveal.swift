import AppKit
import WebKit

// The frame drawn round an element just before the assistant touches it.
//
// This is the answer to "what did it just click?" that costs nothing to read:
// your eyes are on the page, a box lights up where the assistant is about to
// act, and it fades. browser-use does the same before every interaction
// (highlight_interaction_element) and it is the cheapest trust the feature
// has — the model's own one-line summary says what it intends, and this shows
// where.
//
// Two rules, both from browser-use's own hand:
//
//   · it is drawn in Aura's world (Web.world), so the page's scripts can't
//     see it, and no style of the page can win against it;
//   · it never fails the action. A page that refuses the script, a view with
//     no window, an element that has gone — the click happens anyway. The
//     flash is for you, and what it cannot do must never become what the
//     assistant cannot do.

@MainActor
enum AIToolReveal {
    /// How long the frame stays, in seconds: long enough to catch the eye on
    /// the way to the click, short enough not to be in the way of what the
    /// click brings.
    private static let seconds = 0.9

    /// Whether to draw it at all: Settings › AI, on unless turned off.
    static var on: Bool { Shared.prefs.aiToolsReveal }

    /// The element a call is about to touch, framed for a moment. A ref from
    /// a snapshot, already checked to be on the page.
    static func flash(_ element: AIToolSnap.Element, in tab: Tab) {
        guard on, let web = tab.built?.webKit else { return }
        let script = """
        (function () {
          var el = window.__auraRefs && window.__auraRefs.by[\(element.ref)];
          if (!el || !el.isConnected) return false;
          var before = el.style.outline, beforeOffset = el.style.outlineOffset;
          el.style.outline = '2px solid rgba(10, 132, 255, 0.95)';
          el.style.outlineOffset = '2px';
          setTimeout(function () {
            el.style.outline = before;
            el.style.outlineOffset = beforeOffset;
          }, \(Int(seconds * 1000)));
          return true;
        })();
        """
        // Its answer is not the action's problem: whatever the page says is
        // the page's business, and a page that refuses the script is framed
        // by nobody and clicked anyway.
        web.evaluateInSearch(script)
    }

    /// The page's own stylesheet has nothing to say about the frame: it is
    /// set inline, with an !important-free shorthand that wins over the
    /// element's own rule for as long as it is there.
    static let words = Localized("Flash a frame round what the assistant acts on")
}
