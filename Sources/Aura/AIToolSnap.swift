import AppKit
import Foundation
import WebKit

// The numbered list of things on the page a person could touch, and the
// numbers it hands out.
//
// WebKit gives a browser no accessibility tree, so this is a reading of the
// document instead: the elements that are links, buttons, fields, boxes,
// menus or anything else with a role, listed the way Dia and stagehand list
// them — one element a line, indented by how deeply each sits inside the
// last, each with a number in brackets:
//
//     [12] button "Add to Basket"
//     [13] textbox "Email" = person@example.com
//       [14] link "Forgot your password?"
//
// What counts as "a person could see it" is AIPage's own test, and is here
// once for both: hidden, transparent, tiny, clipped away for screen readers
// only, or pushed off the page entirely. A snapshot that listed what nobody
// can see would have the model clicking at nothing.
//
// The numbers live in the page, in Aura's own world (Web.world), so the page's
// own scripts can neither see nor name them. Their rules are:
//
//   · an element keeps its number for as long as it is in the document, so a
//     second snapshot of a page that has grown repeats the numbers it gave;
//   · a number is never given to a second element (the table only grows);
//   · a new document takes every number with it (see Tab.didCommit);
//   · a number that has gone is said to have gone, and the model is told to
//     take a new snapshot — never quietly pointed at whatever took its place.

@MainActor
enum AIToolSnap {
    /// One element, as a call needs it: what it is, what it is called, and
    /// whether it takes typing.
    struct Element {
        let ref: Int
        let role: String
        let name: String
        let takesText: Bool
        let isSecret: Bool
        /// How it is spoken of in a record: `button「Add to Basket」`.
        var described: String {
            let named = name.isEmpty ? role : name
            return "\(role)「\(named)」"
        }
    }

    struct Snapshot {
        let text: String
        let count: Int
    }

    // MARK: - the table in this window

    /// What has been issued in this document, for the errors and for the one
    /// cheap thing a second snapshot is worth saying: nothing has changed.
    /// The elements themselves are on the page; only their numbers are here.
    private struct Registry {
        var issued = Set<Int>()
        var signature: String?
    }

    private static var registries: [ObjectIdentifier: Registry] = [:]

    /// A new document: every number this file gave the old one is gone.
    ///
    /// The numbers stay on the books rather than being forgotten, because
    /// "ref 12 was given to the page you were on and that page is gone" is a
    /// different answer from "there is no 12", and only the first one tells
    /// the model what to do about it — take a new snapshot. What goes is the
    /// signature, since the new document has not been snapped yet.
    static func invalidate(_ tab: Tab) {
        guard var registry = registries[ObjectIdentifier(tab)] else { return }
        registry.signature = nil
        registries[ObjectIdentifier(tab)] = registry
    }

    /// A number this page was given and no longer has. Not the same as a
    /// number it never had, which is a model writing something imaginary.
    static func stale(_ id: String, in tab: Tab) -> Bool {
        guard let number = Int(id), let registry = registries[ObjectIdentifier(tab)] else { return false }
        return registry.issued.contains(number)
    }

    /// A tab that is gone, and with it every number it was given.
    ///
    /// Not folded into `invalidate`: a new document keeps the numbers on the
    /// books so a stale one can be told from an imaginary one, while a closed
    /// tab has no page left to tell anyone anything about. It is forgotten
    /// rather than left behind because these are keyed by the tab's address in
    /// memory, and a tab made after this one freed could be given the same one
    /// — inheriting numbers it never issued.
    static func forget(_ tab: Tab) {
        registries.removeValue(forKey: ObjectIdentifier(tab))
    }

    /// Every number, gone: a test run is done with the page it was using.
    static func reset() {
        registries.removeAll()
    }

    // MARK: - taking one

    /// A snapshot of the page: `scope` limits it to what is inside one
    /// element, `full` to nothing — the whole document rather than the screen
    /// and a screen either side of it.
    static func take(_ tab: Tab, scope: String? = nil, full: Bool = false) async -> Snapshot? {
        var registry = registries[ObjectIdentifier(tab)] ?? Registry()
        let scopeNumber = scope.flatMap { Int($0) }
        let script = script("""
        return window.__auraSnap(\(scopeNumber.map(String.init) ?? "null"), \(full ? "true" : "false"));
        """)
        guard let value = await evaluate(script, in: tab) as? [String: Any],
              let text = value["text"] as? String,
              let count = value["count"] as? Int
        else { return nil }
        // The numbers the page handed out are the ones it now has.
        if let handed = value["refs"] as? [Int] { registry.issued.formUnion(handed) }
        let signature = value["signature"] as? String
        var said = text
        if let last = registry.signature, let signature, last == signature {
            said += "\n\n" + Localized("The page hasn't changed since the last snapshot.")
        }
        registry.signature = signature
        registries[ObjectIdentifier(tab)] = registry
        return Snapshot(text: said, count: count)
    }

    /// One element by its number, or nil when it is not on the page any more.
    static func element(_ id: String, in tab: Tab) async -> Element? {
        guard let number = Int(id) else { return nil }
        let script = script("""
        var el = window.__auraRefs && window.__auraRefs.by[\(number)];
        if (!el || !el.isConnected || !shown(el)) return null;
        return { ref: \(number), role: role(el), name: name(el), text: takes(el), secret: secret(el) };
        """)
        guard let value = await evaluate(script, in: tab) as? [String: Any],
              let role = value["role"] as? String
        else { return nil }
        return Element(ref: number, role: role,
                       name: (value["name"] as? String) ?? "",
                       takesText: (value["text"] as? Bool) ?? false,
                       isSecret: (value["secret"] as? Bool) ?? false)
    }

    /// Where its middle is, in the page's points, scrolled into view first.
    static func point(of element: Element, in tab: Tab) async -> CGPoint? {
        let script = script("""
        var el = window.__auraRefs && window.__auraRefs.by[\(element.ref)];
        if (!el || !el.isConnected) return null;
        el.scrollIntoView({ block: 'center', inline: 'nearest' });
        var r = el.getBoundingClientRect();
        if (r.width < 1 || r.height < 1) return null;
        return [r.left + r.width / 2, r.top + r.height / 2];
        """)
        guard let value = await evaluate(script, in: tab) as? [Double], value.count == 2 else { return nil }
        return CGPoint(x: value[0], y: value[1])
    }

    /// The element a number names, as a JavaScript expression the shared
    /// helpers work on — so typing into a field and sending a form are
    /// PageAct's, and never a second copy of them.
    private static func target(_ element: Element) -> String {
        "window.__auraRefs && window.__auraRefs.by[\(element.ref)]"
    }

    /// The value typed in, through PageAct's own typing: the field's setter
    /// and the events a change sends, so React and Vue notice.
    static func fill(_ element: Element, with value: String, in tab: Tab) async -> Bool {
        // PageAct's act is a function of its own, and returns "ok" from it:
        // wrapping it in this file's script would throw that away.
        let script = PageAct.act(.type, element: target(element),
                                 name: "ref \(element.ref)", text: value)
        return (await evaluate(script, in: tab) as? String) == "ok"
    }

    /// The form around the element, sent. Nil when there is no form.
    static func submit(_ element: Element, in tab: Tab) async -> Bool? {
        let script = PageAct.act(.submit, element: target(element), name: "ref \(element.ref)")
        guard let said = await evaluate(script, in: tab) as? String else { return nil }
        return said == "ok"
    }

    /// The element taken, ready for a key: focus is what a key press goes to.
    static func focus(_ element: Element, in tab: Tab) async {
        _ = await evaluate(script("""
        var el = window.__auraRefs && window.__auraRefs.by[\(element.ref)];
        if (el && el.focus) el.focus();
        return true;
        """), in: tab)
    }

    static func intoView(_ element: Element, in tab: Tab) async {
        _ = await evaluate(script("""
        var el = window.__auraRefs && window.__auraRefs.by[\(element.ref)];
        if (el && el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'nearest' });
        return true;
        """), in: tab)
    }

    /// The words around the element, for the classifier: a button called
    /// "Continue" inside a card that says "Confirm payment" is a payment
    /// whatever the button itself says.
    static func formText(of element: Element, in tab: Tab) async -> String {
        let script = script("""
        var el = window.__auraRefs && window.__auraRefs.by[\(element.ref)];
        if (!el) return '';
        var form = el.form || el.closest('form');
        var scope = form || el.closest('section, article, main, [role=dialog], [role=form]');
        if (!scope) return '';
        return String(scope.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 400);
        """)
        return (await evaluate(script, in: tab) as? String) ?? ""
    }

    /// Whether the page's visible words have this in them, and what was found
    /// — the page's own casing, so the record and the model see the real one.
    static func contains(_ text: String, in tab: Tab) async -> String? {
        let script = script("""
        var want = \(PageAct.quoted(text)), body = document.body;
        if (!body) return null;
        if ((body.innerText || '').toLowerCase().indexOf(want.toLowerCase()) < 0) return null;
        return want;
        """)
        return await evaluate(script, in: tab) as? String
    }

    /// JavaScript in Aura's world, where the table of elements lives, and the
    /// answer as a value.
    private static func evaluate(_ js: String, in tab: Tab) async -> Any? {
        let web = tab.built?.webKit ?? tab.web.webKit
        return await withCheckedContinuation { done in
            web.evaluateJavaScript(js, in: nil, in: Web.world) { result in
                done.resume(returning: try? result.get())
            }
        }
    }

    // MARK: - the script

    /// One script: the helpers, then `body`, shut together. Everything here
    /// goes through this, so a body can `return` and nobody has to remember
    /// whose function the return belongs to.
    static func script(_ body: String) -> String {
        helpers + "\n" + body + "\n})();"
    }

    /// What every script here needs first: the table, the visible test, and
    /// the words for an element. It opens Aura's side of the page and does not
    /// close it: `script(_:)` puts a caller's body inside and shuts it.
    ///
    /// The visible test is AIPage's, and has to stay AIPage's: two answers to
    /// "can a person see this" would mean a snapshot that lists what the page
    /// reading calls invisible, or the other way round.
    static let helpers = """
    (function () {
      var SKIP = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, IFRAME: 1, FRAME: 1, OBJECT: 1, EMBED: 1,
                   OPTION: 1, HEAD: 1, SVG: 1, CANVAS: 1, VIDEO: 1, AUDIO: 1 };
      var refs = window.__auraRefs || (window.__auraRefs = { by: {}, next: 1 });
      var width = document.documentElement.scrollWidth, height = document.documentElement.scrollHeight;

      function shown(el) {
        if (el.hidden || el.getAttribute('aria-hidden') === 'true' || el.inert) return false;
        var s = getComputedStyle(el);
        if (s.display === 'none' || s.visibility === 'hidden' || s.visibility === 'collapse') return false;
        if (parseFloat(s.opacity) < 0.1 || s.contentVisibility === 'hidden') return false;
        if (parseFloat(s.fontSize) < 6) return false;
        if ((s.clip && s.clip.indexOf('rect(0') === 0) || /circle\\(0/.test(s.clipPath || '')) return false;
        var inset = /inset\\((\\d+)%/.exec(s.clipPath || '');
        if (inset && +inset[1] >= 50) return false;
        var faded = /opacity\\(([\\d.]+)(%?)\\)/.exec(s.filter || '');
        if (faded && +faded[1] / (faded[2] ? 100 : 1) < 0.1) return false;
        if (parseFloat(s.textIndent) < -500) return false;
        var r = el.getBoundingClientRect();
        if ((r.width < 2 || r.height < 2) && s.overflow !== 'visible') return false;
        if (r.width < 1 && r.height < 1) return false;
        var x = r.right + window.scrollX, y = r.bottom + window.scrollY;
        if (x < 0 || y < 0 || r.left + window.scrollX > width + 50) return false;
        return true;
      }

      function role(el) {
        var said = (el.getAttribute('role') || '').toLowerCase();
        if (said && said !== 'presentation' && said !== 'none') return said;
        var tag = el.tagName.toLowerCase();
        if (tag === 'a') return 'link';
        if (tag === 'button' || tag === 'summary') return 'button';
        if (tag === 'select') return 'combobox';
        if (tag === 'textarea') return 'textbox';
        if (tag === 'input') {
          var type = (el.type || 'text').toLowerCase();
          if (type === 'password') return 'password';
          if (type === 'submit' || type === 'button' || type === 'reset' || type === 'image') return 'button';
          if (type === 'checkbox' || type === 'radio' || type === 'file') return type;
          if (type === 'range') return 'slider';
          return 'textbox';
        }
        if (el.isContentEditable) return 'textbox';
        return tag;
      }

      function name(el) {
        var t = el.getAttribute('aria-label') || '';
        if (!t) {
          var by = el.getAttribute('aria-labelledby');
          if (by) {
            by.split(/\\s+/).forEach(function (id) {
              var n = document.getElementById(id);
              if (n) t += ' ' + (n.innerText || n.textContent || '');
            });
          }
        }
        if (!t) t = el.getAttribute('title') || '';
        if (!t) t = el.getAttribute('placeholder') || '';
        if (!t) t = el.getAttribute('alt') || '';
        if (!t && el.labels && el.labels.length) t = el.labels[0].innerText || '';
        if (!t) t = el.innerText || el.textContent || '';
        if (!t && el.tagName === 'INPUT' && el.type !== 'password') t = el.value || '';
        return String(t).replace(/\\s+/g, ' ').trim().slice(0, 80);
      }

      function takes(el) {
        var r = role(el);
        return r === 'textbox' || r === 'password' || r === 'searchbox' || r === 'combobox' || el.isContentEditable === true;
      }

      function secret(el) { return role(el) === 'password'; }

      function value(el) {
        var r = role(el);
        if (r === 'password' || r === 'file') return '';
        if (el.isContentEditable) return String(el.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 60);
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
          return String(el.value == null ? '' : el.value).replace(/\\s+/g, ' ').trim().slice(0, 60);
        }
        return '';
      }

      function mark(el) {
        var r = role(el);
        if (r !== 'checkbox' && r !== 'radio' && r !== 'switch') return '';
        var on = el.checked === true || el.getAttribute('aria-checked') === 'true';
        return on ? '\\u2713' : '';
      }

      function number(el) {
        for (var key in refs.by) { if (refs.by[key] === el) return +key; }
        var n = refs.next++;
        refs.by[n] = el;
        // A page that keeps changing ends up with a table that keeps growing:
        // its oldest numbers are dropped, and go stale, which the model is
        // told to expect of a page like that.
        var keys = Object.keys(refs.by);
        if (keys.length > 2000) {
          for (var i = 0; i < keys.length - 2000; i++) delete refs.by[keys[i]];
        }
        return n;
      }

      window.__auraSnap = function (scope, full) {
        var SEL = 'a[href], button, input, textarea, select, summary, ' +
          '[contenteditable=""], [contenteditable="true"], [onclick], ' +
          '[role=button], [role=link], [role=textbox], [role=searchbox], [role=checkbox], [role=radio], ' +
          '[role=combobox], [role=switch], [role=tab], [role=menuitem], [role=menuitemcheckbox], ' +
          '[role=option], [role=slider], [role=treeitem], [tabindex]:not([tabindex="-1"])';
        var root = scope && refs.by[scope] && refs.by[scope].isConnected ? refs.by[scope] : document.body;
        if (!root) return null;
        var found = [], all = root.querySelectorAll(SEL);
        for (var i = 0; i < all.length && i < 5000; i++) {
          var el = all[i];
          if (SKIP[el.tagName.toUpperCase()] || el.disabled === true) continue;
          if (!shown(el)) continue;
          found.push(el);
        }
        // One line a thing to touch: an element inside another listed one is
        // said by its outer one, as Dia lists them.
        var listed = [];
        for (var j = 0; j < found.length; j++) {
          var up = found[j].parentElement, nested = false;
          while (up && up !== root) { if (found.indexOf(up) >= 0) { nested = true; break; } up = up.parentElement; }
          if (!nested) listed.push(found[j]);
        }
        // One screen either side of what is on screen, unless the whole
        // document was asked for.
        var screenHeight = window.innerHeight || 800;
        var top = window.scrollY - screenHeight, bottom = window.scrollY + screenHeight * 2;
        var lines = [], refsOut = [], signature = [], off = 0;
        for (var k = 0; k < listed.length; k++) {
          var node = listed[k], box = node.getBoundingClientRect();
          var y = box.top + window.scrollY;
          if (!full && (y + box.height < top || y > bottom)) { off++; continue; }
          var n = number(node);
          var level = 0, p = node.parentElement;
          while (p && p !== root && level < 6) { if (listed.indexOf(p) >= 0) level++; p = p.parentElement; }
          var line = new Array(level + 1).join('  ') + '[' + n + '] ' + role(node);
          var named = name(node);
          if (named) line += ' "' + named.replace(/"/g, '\\\\"') + '"';
          var v = value(node), c = mark(node);
          if (v) line += ' = ' + v;
          if (c) line += ' ' + c;
          lines.push(line);
          refsOut.push(n);
          signature.push(line);
        }
        var text = lines.join('\\n');
        if (!lines.length) text = '(nothing on this page can be clicked or typed into)';
        var tail = [];
        if (off > 0) tail.push(off + ' more are out of view; ask for full: true to list them');
        if (scope && root !== document.body) tail.push('listed inside element [' + scope + '] only');
        if (tail.length) text += '\\n\\n(' + tail.join('; ') + ')';
        return { text: text, count: lines.length, refs: refsOut, signature: signature.join('\\n') };
      };
    """
}
