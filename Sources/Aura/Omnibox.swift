import SwiftUI
import AppKit

/// Arc's command bar: one field and one panel, and the few places it thinks you
/// mean. It answers to addresses, to words worth searching for, to the pages
/// already open and to the commands the app itself takes — the rows below the
/// field say which of those each one is, rather than the field deciding before
/// you have finished typing. Type something that is none of them and it
/// shivers and says so, rather than quietly handing your keystrokes to a
/// search engine.
struct Omnibox: View {
    @ObservedObject var browser: Browser
    /// Raised over a page by ⌘T or ⌘L, rather than standing on an empty tab.
    let over: Bool

    /// One row of the list, whatever it holds. Fixed, so the panel knows how
    /// tall it is before it is drawn (see `content`), and so a longer row of
    /// words cuts itself short rather than making the bar breathe.
    static let rowHeight: CGFloat = 36
    /// The air around the rows, above and below.
    private static let listInset: CGFloat = 12
    /// How far above the middle the field sits: dead centre reads as low,
    /// because the strip at the top isn't part of what the eye is measuring.
    private static let lift: CGFloat = 30

    @State private var shake: CGFloat = 0
    @State private var refused = false
    /// The row the pointer is on, by what it offers rather than by where it
    /// sits: the list under it is rebuilt with every keystroke.
    @State private var pointing: Suggestion.ID?

    /// Sized to a pane of a split rather than to the window.
    var fitted = false

    /// The rows the bar has to draw: the site's own search, then the list.
    private var rows: Int { browser.offers.count + (browser.siteOffer == nil ? 0 : 1) }

    /// What the list adds below the field. Known exactly rather than measured,
    /// because the field is positioned against it: the rows hang from under the
    /// field instead of pushing it about.
    private var listHeight: CGFloat {
        rows == 0 ? 0 : CGFloat(rows) * Self.rowHeight + Self.listInset
    }

    var body: some View {
        if fitted {
            GeometryReader { geometry in
                content(width: min(Metrics.fieldWidth, max(0, geometry.size.width - 28)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            content(width: Metrics.fieldWidth)
        }
    }

    private func content(width: CGFloat) -> some View {
        ZStack {
            if over {
                // The page stays as it was, the panel over it as Arc's command
                // bar is over its page: nothing dimmed, because the page is
                // still yours to read behind the field. This sheet is clear —
                // it is here only to take the press that puts the field away.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea(.all, edges: fitted ? [] : .all)
                    .onTapGesture { browser.dismiss() }
            }

            panel(width: width)
                // The field stays exactly where it stood without a list, and
                // the rows take their room below it: half the list's height
                // given back above the middle, since a centred panel of a new
                // height would otherwise carry the field up with it, out from
                // under what is being typed.
                .offset(y: listHeight / 2 - Self.lift)
                .modifier(Shake(travel: shake))
                // The list's arrival and its leaving are animated from here,
                // briefly, and its rows follow what was typed or pasted at
                // once: sliding into place on a spring between keystrokes, they
                // trailed behind the field.
                .animation(Motion.quick, value: rows)
                .animation(Motion.settle, value: refused)
                .onChange(of: browser.refusals) { _, _ in
                    shake = 0
                    refused = true
                    withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
                }
                .onChange(of: browser.typed) { _, _ in
                    withAnimation(Motion.quick) { refused = false }
                }
        }
    }

    /// The bar: the field at the top, the list under it, one ground and one
    /// edge around both. Arc's is one panel for the same reason — a list in a
    /// box of its own reads as something that happened to the field rather
    /// than as what the field is saying.
    private func panel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            fieldRow
            if rows > 0 {
                list
                    .transition(.opacity)
            }
        }
        .frame(width: width)
        .background {
            ZStack {
                // A slow, almost invisible breath behind the bar. It is the
                // only thing on an empty tab, and a thing that never moves at
                // all reads as a picture of an app rather than an app.
                Breath()

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.ground)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    refused ? Color.red.opacity(0.35) : Palette.hairline,
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.18), radius: 38, y: 14)
    }

    /// The field itself, with the glass Arc's bar wears before what is typed:
    /// the bar takes words and commands as well as addresses now, and nothing
    /// on the panel says so unless this does.
    private var fieldRow: some View {
        HStack(spacing: 10) {
            if let site = browser.siteChip {
                SiteChip(site: site)
                    .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16)
            }
            AddressField(browser: browser)
        }
            .animation(Motion.quick, value: browser.siteChip)
            .frame(height: 22)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    /// What it thinks you mean, in the order Arc's bar keeps: what the app
    /// itself can do, the pages open already, the places you have been, and
    /// last the words you typed. A page you have open comes before a page you
    /// merely visited, because taking it costs nothing.
    ///
    /// One row each, the same height, so the panel below the field is a
    /// known strip rather than whatever the text came to.
    private var list: some View {
        VStack(spacing: 0) {
            if let site = browser.siteOffer {
                SiteOfferRow(site: site)
                    .contentShape(Rectangle())
                    .onTapGesture { _ = browser.lockSiteOffer() }
            }
            ForEach(Array(browser.offers.enumerated()), id: \.element.id) { index, offer in
                Row(
                    offer: offer,
                    // A list shows one marked row: the pointer's while it is
                    // over the list, the keys' while it is not.
                    picked: pointing == nil ? browser.picked == index : pointing == offer.id,
                    onHover: { over in pointing = over ? offer.id : nil }
                )
                .contentShape(Rectangle())
                .onTapGesture { browser.take(offer) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    /// One row of the list, here and under the field in the tab.
    ///
    /// What a row is decides what it says, as it does in Arc's bar: a page
    /// already open is named the way its tab is named and carries the address
    /// it sits at, a place you have been is named by its title with the address
    /// beside it, and a search by the words typed with the engine that would
    /// answer them.
    struct Row: View {
        /// Every row is the same until one is marked: what a row is decides
        /// what it says, and only the mark is the pointer's and the keys' to
        /// fight over.
        init(offer: Suggestion, picked: Bool = false, showsHint: Bool = true,
             onHover: @escaping (Bool) -> Void = { _ in }) {
            self.offer = offer
            self.picked = picked
            self.showsHint = showsHint
            self.onHover = onHover
        }

        let offer: Suggestion
        /// Whether this is the one marked row: the one the arrow keys have
        /// walked to, or the one under the pointer, which takes the mark from
        /// it. Changes nothing but the look of the row.
        let picked: Bool
        /// Told when the pointer comes and goes, so the list can keep one mark
        /// in it.
        let onHover: (Bool) -> Void
        /// Whether a row for a page already open says so at its end. The
        /// switcher is nothing but those, so it says it once, by being.
        var showsHint = true

        var body: some View {
            HStack(spacing: 10) {
                mark
                    .frame(width: 16, height: 16)
                Text(head)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !tail.isEmpty, tail.caseInsensitiveCompare(head) != .orderedSame {
                    Text(tail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // The name is what is being looked for: a long address
                        // gives way to it rather than the other way round.
                        .layoutPriority(-1)
                }
                Spacer(minLength: 8)
                if showsHint, case .open = offer.kind {
                    // What taking this row does, at the end of it: Arc's
                    // "Switch to Tab", with the arrow its rows carry. The
                    // switcher is told not to ask, every row there being one.
                    Text(Localized("Switch to Tab"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .fixedSize()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 10)
            // One height for every row, whatever it holds: the panel's own
            // height is worked out from it (see Omnibox.listHeight).
            .frame(height: Omnibox.rowHeight)
            .background {
                // One grey for the marked row, whichever put the mark there:
                // deep enough to be seen at a glance, and never the ink, which
                // is for words rather than for grounds.
                if picked {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.pick)
                }
            }
            .onHover(perform: onHover)
            .animation(Motion.quick, value: picked)
        }

        /// The site's own icon where this Mac has it, and the glyph that says
        /// what kind of thing the row is where it hasn't.
        @ViewBuilder
        private var mark: some View {
            switch offer.kind {
            case .search:
                // A search sent to a site you have been to says so with the
                // site rather than a magnifying glass. Nothing is fetched for
                // one that isn't known; the glass is what the row wears until
                // then.
                if let icon = favicon {
                    icon
                } else {
                    glyph("magnifyingglass")
                }
            case .suggested:
                // The engine's own words: always the glass, so they read as
                // searches rather than places.
                glyph("magnifyingglass")
            case .open:
                // Already open: naming it takes you back to it rather than
                // opening a second copy. Its own icon when this Mac has it, as
                // a tab's row does; the dot when it hasn't.
                if let icon = favicon {
                    icon
                } else {
                    Circle()
                        .fill(Palette.ink.opacity(0.55))
                        .frame(width: 5, height: 5)
                }
            case .visited, .known:
                // Somewhere you have been: its icon where the Mac has one, and
                // no mark at all where it hasn't — a grey square standing in
                // for a site nobody has drawn yet is worse than the address
                // saying it plainly.
                if let icon = favicon {
                    icon
                } else {
                    Color.clear
                }
            case .command:
                glyph("command")
            }
        }

        private var favicon: AnyView? {
            guard let site = Favicons.site(offer.url),
                  let icon = Favicons.shared.cached(site) else { return nil }
            return AnyView(
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            )
        }

        private func glyph(_ name: String) -> some View {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
        }

        /// What the row is called. A tab's name for a page already open, a
        /// title for a place you have been, the words themselves for a search.
        private var head: String {
            switch offer.kind {
            case .open:
                return offer.key
            case .visited, .known:
                return offer.title.isEmpty ? Address.withoutWWW(offer.key) : offer.title
            default:
                return offer.kind == .suggested ? offer.key : Address.withoutWWW(offer.key)
            }
        }

        /// Where it is, or who would answer it: quieter, and after the name.
        /// A `key` keeps its www for completing and going there; the row reads
        /// without it, as it did before.
        private var tail: String {
            switch offer.kind {
            case .open:
                return offer.title.isEmpty ? "" : Address.withoutWWW(offer.title)
            case .visited, .known:
                return offer.title.isEmpty ? "" : Address.withoutWWW(offer.key)
            case .search:
                return offer.title
            default:
                return ""
            }
        }
    }
}

/// A site's icon when this Mac has it, or a glass.
private struct SiteIcon: View {
    let site: SearchSite
    var body: some View {
        let host = site.host.split(separator: "/").first.map(String.init) ?? site.host
        if let icon = Favicons.shared.cached(host) ?? Favicons.shared.cached("www." + host) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 14, height: 14)
        }
    }
}

/// The site Tab put in the field: its icon and name, in the field's grey,
/// before what is typed.
private struct SiteChip: View {
    let site: SearchSite
    var body: some View {
        HStack(spacing: 6) {
            SiteIcon(site: site)
            Text(site.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localized("Searching \(site.name)"))
    }
}

/// "Search Reddit", first in the list, with the key that takes it.
private struct SiteOfferRow: View {
    let site: SearchSite
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(site: site)
            Text(Localized("Search \(site.name)"))
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Tab")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 10)
        // The same height as the rows under it: it is the first of them.
        .frame(height: Omnibox.rowHeight)
        .background {
            if hovering { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.hover) }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localized("Search \(site.name), press Tab"))
    }
}

/// The breath under the field: a soft shape of ink, blurred, moved by Core
/// Animation. Animated by SwiftUI, it was drawn again on the main thread
/// every frame for as long as an empty tab was showing — 18% of a core with
/// the window doing nothing (24 Sep 2026). As a layer's shadow, breathed by
/// Core Animation, it is played in the render server and costs the app
/// nothing; and it is a layer, not a second SwiftUI view to build before
/// the first frame.
private struct Breath: NSViewRepresentable {
    /// As dark as the shape it replaces, 5% ink blurred by 26: a shadow of
    /// the same radius comes out at 0.7 of the darkness at equal strength,
    /// measured on pictures of both (24 Sep 2026), so 7%.
    static let strength: Swift.Float = 0.07

    func makeNSView(context: Context) -> NSView { Lung() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Lung: NSView {
        private let glow = CALayer()
        private var breathed: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            glow.shadowOpacity = Breath.strength
            glow.shadowOffset = .zero
            glow.shadowRadius = 26
            layer?.addSublayer(glow)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The ink is the look's: light on a dark window, dark on a light one.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
        }

        override func layout() {
            super.layout()
            guard bounds.size != breathed, bounds.width > 0 else { return }
            breathed = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.bounds = bounds
            glow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            glow.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 26, cornerHeight: 26, transform: nil)
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
            CATransaction.commit()
            // From 0.97 to 1.03, from 0.65 to full, 2.6 s each way, for as
            // long as the field is there.
            let size = CABasicAnimation(keyPath: "transform.scale")
            size.fromValue = 0.97
            size.toValue = 1.03
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.65
            fade.toValue = 1.0
            let both = CAAnimationGroup()
            both.animations = [size, fade]
            both.duration = 2.6
            both.autoreverses = true
            both.repeatCount = .infinity
            both.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(both, forKey: "breath")
        }
    }
}

/// The field itself, in AppKit.
///
/// SwiftUI's TextField can hold a string and nothing else, and the whole point
/// here is the part you didn't type: the rest of the address, already there and
/// selected, so carrying on typing replaces it and Return accepts it. That
/// needs a real text field and its delegate.
struct AddressField: NSViewRepresentable {
    @ObservedObject var browser: Browser

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15.5)
        field.textColor = Palette.NS.ink
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        // Scrolls with the caret, so a long address can be read and edited
        // all the way along rather than cut off at the field's edge.
        field.cell?.isScrollable = true
        // SwiftUI picks its own colour for a placeholder, and on a pale ground
        // that colour was near-white.
        field.placeholderAttributedString = NSAttributedString(
            string: "Search or enter a web address".localized,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15.5),
                .foregroundColor: NSColor(Palette.ink.opacity(0.3)),
            ]
        )
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser

        // Only when something other than typing changed it — ⌘L arriving with
        // an address, a walk through the list, a submit clearing it.
        //
        // Comparing against the field's own text instead would undo every
        // backspace: deleting leaves the field shorter than what the browser
        // still considers complete, and the next update would helpfully type
        // it back in. That is a field you cannot shorten, and it reads exactly
        // like one that has stopped responding.
        let want = browser.completed
        if want != coordinator.synced {
            coordinator.synced = want
            field.stringValue = want
            coordinator.select(from: browser.typed.count, in: field)
        }

        if coordinator.answered != browser.focusRequest {
            coordinator.answered = browser.focusRequest
            DispatchQueue.main.async { coordinator.focus(field) }
        }
    }

    /// The field, told when it lands in a window.
    ///
    /// SwiftUI makes the view and updates it before it is in one, and with
    /// Split View on it comes only once the stage has said where the page is,
    /// a turn of the run loop later. Asked for the keys before then, the
    /// field had no window to ask: the request went nowhere and nothing asked
    /// again, so ⌘T left a field with no caret and typing that went nowhere
    /// until it was clicked. Now the request waits for the window.
    final class Field: NSTextField {
        var arrived: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, let arrived else { return }
            self.arrived = nil
            arrived()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser
        var answered = -1
        /// The last value pushed in from the browser side, so an update can
        /// tell a change worth applying from one it made itself.
        var synced = ""

        /// A backspace has to be allowed to actually take a letter off. Without
        /// this the field puts the same letter straight back as a completion
        /// and the address can never be shortened.
        private var deleting = false

        init(browser: Browser) {
            self.browser = browser
        }

        /// The keys to the field, now if it is in a window, or the moment it is.
        @MainActor func focus(_ field: Field) {
            guard let window = field.window else {
                field.arrived = { [weak self, weak field] in
                    DispatchQueue.main.async {
                        guard let self, let field, self.browser.fieldShowing else { return }
                        self.focus(field)
                    }
                }
                return
            }
            field.arrived = nil
            window.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            defer { browser.fieldFocused(in: window) }
            // The system paints selected text as a block of accent colour,
            // which over this pale field is the loudest thing in the
            // window. A tenth of the ink says "selected" quietly enough.
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
                .foregroundColor: Palette.NS.ink,
            ]
            // A draft come back to its blank tab is carried on, not typed
            // over: the caret after it. An address ⌘L raises is selected whole.
            if browser.active?.isBlank == true, !browser.typed.isEmpty {
                select(from: browser.typed.count, in: field)
            } else {
                editor.selectAll(nil)
            }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let text = field.stringValue

            browser.typed = text
            guard !deleting, let ending = browser.ending else {
                if deleting { browser.stopCompleting() }
                deleting = false
                synced = browser.completed
                return
            }
            deleting = false

            field.stringValue = text + ending
            synced = field.stringValue
            select(from: text.count, in: field)
        }

        /// The part after the caret, shown as selected, so the next keystroke
        /// replaces it and Return takes it.
        func select(from start: Int, in field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
                .foregroundColor: Palette.NS.ink,
            ]
            let length = field.stringValue.count
            guard start <= length else { return }
            editor.selectedRange = NSRange(location: start, length: length - start)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy command: Selector
        ) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                browser.submit()
                return true
            case #selector(NSResponder.moveDown(_:)):
                browser.walk(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                browser.walk(-1)
                return true
            case #selector(NSResponder.deleteWordBackward(_:)):
                // ⌥⌫ over an offered ending lets go of it and takes the last
                // word typed, as it does with no ending there. Left to the
                // text view it would only take the selected ending.
                deleting = true
                let selected = textView.selectedRange()
                guard browser.ending != nil, selected.length > 0,
                      NSMaxRange(selected) == (textView.string as NSString).length
                else { return false }
                textView.delete(nil)
                deleting = true
                textView.deleteWordBackward(nil)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty && browser.siteChip != nil:
                // ⌫ on an empty field takes the site out of it.
                browser.siteChip = nil
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordForward(_:)):
                deleting = true
                return false
            default:
                return false
            }
        }
    }
}
