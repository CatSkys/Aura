import AppKit
import WebKit

// The things this browser does to a page, in one place, for the two callers
// that do them: the bench (`./bench tap`, `click`, `type`, `submit`, `key`)
// and the AI's tools (AITool).
//
// They are here rather than in either caller because they have to stay the
// same act. A click the bench sends and a click the assistant sends are both
// real mouse events handed to the page's view — trusted, as a hand's are,
// which is what a password manager insists on — and two copies of that would
// drift apart the first time one of them was fixed.
//
// Nothing here is gated: whether an act may happen is the caller's question.
// The bench asks `Store.testing`; the assistant asks the person (AIToolRisk).

@MainActor
enum PageAct {
    /// What is done to an element, for each of the two callers.
    enum Verb {
        case click
        case type
        case submit
    }

    // MARK: - in the page

    /// An element found by a selector — the bench's way of naming one, with
    /// `text=Words` for a button or link by its own words — in the page's
    /// world, where a click on it is the page's own click.
    static func found(_ selector: String) -> String {
        let sel = quoted(selector)
        return """
        (function () {
          var s = \(sel), el = null;
          if (s.indexOf('text=') === 0) {
            var want = s.slice(5).trim().toLowerCase();
            el = Array.prototype.find.call(document.querySelectorAll('button, a, [role=button], input[type=submit]'), function (e) {
              return ((e.innerText || e.value || '').trim().toLowerCase()) === want;
            }) || null;
          } else {
            el = document.querySelector(s);
          }
          return el;
        })()
        """
    }

    /// Where an element's middle is, in the page's own points, scrolled into
    /// view first.
    static func middle(of selector: String, named name: String? = nil) -> String {
        """
        (function () {
          var el = \(found(selector));
          if (!el) return null;
          el.scrollIntoView({ block: 'center', inline: 'nearest' });
          var r = el.getBoundingClientRect();
          return [r.left + r.width / 2, r.top + r.height / 2];
        })()
        """
    }

    /// Click, type into, or submit the element an expression names.
    ///
    /// Typing goes through the field's own setter and fires the events a
    /// keystroke would, the same as the password filler, so frameworks
    /// notice. `name` is how the element is spoken of when something goes
    /// wrong — the selector the bench was given, or `ref 12`.
    static func act(_ verb: Verb, element: String, name: String, text: String = "") -> String {
        let said = quoted(name)
        let value = quoted(text)
        return """
        (function () {
          var el = \(element);
          if (!el) return 'nothing matches ' + \(said);
          if (el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'nearest' });
          var verb = '\(verb == .click ? "click" : verb == .submit ? "submit" : "type")';
          if (verb === 'click') { el.focus && el.focus(); el.click(); return 'ok'; }
          if (verb === 'submit') {
            var form = el.tagName === 'FORM' ? el : el.form || el.closest('form');
            if (!form) return 'no form around ' + \(said);
            if (form.requestSubmit) form.requestSubmit(); else form.submit();
            return 'ok';
          }
          el.focus && el.focus();
          var value = \(value);
          if (el.isContentEditable) {
            el.textContent = value;
            el.dispatchEvent(new InputEvent('input', { bubbles: true, data: value, inputType: 'insertText' }));
            return 'ok';
          }
          var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
          var setter = Object.getOwnPropertyDescriptor(proto, 'value');
          if (setter && setter.set) setter.set.call(el, value); else el.value = value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return 'ok';
        })()
        """
    }

    /// A text as JavaScript says it, quote and all.
    static func quoted(_ text: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [text]))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    // MARK: - the mouse

    /// A real click on a point of the page's view: mouse events handed to the
    /// view, which WebKit takes as a hand's. `middle` is the middle button.
    ///
    /// False when the view has no window to make an event for — a tab that
    /// isn't on screen can't be clicked.
    @discardableResult
    static func press(_ view: WKWebView, at point: CGPoint,
                      modifiers: NSEvent.ModifierFlags = [], middle: Bool = false) -> Bool {
        guard let window = view.window else { return false }
        let local = NSPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
        let spot = view.convert(local, to: nil)
        let types: [NSEvent.EventType] = middle ? [.otherMouseDown, .otherMouseUp] : [.leftMouseDown, .leftMouseUp]
        var sent = false
        for type in types {
            guard var event = NSEvent.mouseEvent(
                with: type, location: spot, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == types[0] ? 1 : 0
            ) else { continue }
            if middle, let raw = event.cgEvent {
                raw.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                if let again = NSEvent(cgEvent: raw) { event = again }
            }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .otherMouseDown: view.otherMouseDown(with: event)
            case .otherMouseUp: view.otherMouseUp(with: event)
            default: view.mouseUp(with: event)
            }
            sent = true
        }
        return sent
    }

    // MARK: - the keys

    /// One key, as a keyboard sends it: the name the assistant asks for, the
    /// code macOS gives it, and what it types.
    struct Key: Equatable {
        let name: String
        let code: UInt16
        let chars: String
        /// Enter sends a form; nothing else does on its own.
        var submits: Bool { name == "Enter" }

        init?(name wanted: String) {
            let name = wanted.trimmingCharacters(in: .whitespaces)
            guard let key = Key.all.first(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
            self = key
        }

        private init(_ name: String, _ code: UInt16, _ chars: String) {
            self.name = name
            self.code = code
            self.chars = chars
        }

        /// The keys a page does something with, by the names a person would
        /// say them by.
        static let all: [Key] = [
            Key("Enter", 36, "\r"), Key("Tab", 48, "\t"), Key("Escape", 53, "\u{1b}"),
            Key("Space", 49, " "), Key("Backspace", 51, "\u{8}"), Key("Delete", 117, "\u{7f}"),
            Key("ArrowUp", 126, "\u{f700}"), Key("ArrowDown", 125, "\u{f701}"),
            Key("ArrowLeft", 123, "\u{f702}"), Key("ArrowRight", 124, "\u{f703}"),
            Key("PageUp", 116, "\u{f72c}"), Key("PageDown", 121, "\u{f72d}"),
            Key("Home", 115, "\u{f729}"), Key("End", 119, "\u{f72b}"),
        ]
    }

    /// A key pressed on a view, as a hand's is: keyDown then keyUp, handed to
    /// the view itself. False when the view has no window.
    @discardableResult
    static func press(_ key: Key, in view: WKWebView) -> Bool {
        guard let window = view.window else { return false }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: key.chars, charactersIgnoringModifiers: key.chars,
                isARepeat: false, keyCode: key.code
            ) else { continue }
            if type == .keyDown { view.keyDown(with: event) } else { view.keyUp(with: event) }
        }
        return true
    }

    /// A character typed at a view, code and all, for the bench's `key`.
    static func code(for character: Character) -> UInt16 {
        let codes: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
            "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ]
        return codes[Character(character.lowercased())] ?? 49
    }
}
