import AppKit
import SwiftUI

// What the assistant did, as the conversation shows it after the fact: Dia's
// own rows down a rail on the left — a dot or a glyph in the margin, a line
// between them, and a title per thing that happened.
//
// This is the answer to "what did it actually do", and the reason `say` alone
// was not enough: the model's one line is what you watch while it works, and
// gone when the turn ends. A row is written by the tool that ran, not by the
// model, and it stays with the answer.
//
// Read off Dia's app (web-chat-resources/dist/app/immutable): the rows are
// `.row[data-item-type=toolCall]` on a `--dia-rail` — a 2pt line at 18pt to the
// left of the text, a 16pt marker centred on it, dots 6pt across. The titles
// are its own grammar, taken exactly (`nodes/4.DUxGFY7h.js`):
//
//   "Searched the web (2 times)"   one tool, done more than once, counted
//   "Opened tabs" → "Opened 1 tab" a heading, and what it came to underneath
//   "Always-allowed action"        a call that went through without asking
//   "Read 1 tab"                   and the thing it read named under it
//
// A step keeps what happened rather than what was intended, so a call that
// failed says so; a step whose tool never ran is not written at all.

/// One row of the rail. Two kinds share it, because Dia's rail holds both in
/// one order: a tool call, and the model's own line between them.
struct AIToolStep: Identifiable, Equatable, Codable {
    /// Which of the two this is.
    enum Kind: String, Codable {
        /// The model's own line — `say`. A dot in the margin and grey words:
        /// what it is doing, in its own voice.
        case note
        /// Something that ran. A glyph, and a title in ink, because this is
        /// the record and the note is the narration.
        case tool
    }

    var id = UUID()
    /// Note or tool — the only thing the rail draws differently.
    var kind = Kind.tool
    /// The tool that ran, by the name the model called it.
    var tool: String
    /// What it is called on the rail: Dia's grammar, not the model's words.
    var title: String
    /// What came of it, under the title, when there is anything to say —
    /// "Opened 1 tab", "Read 1 tab", the address that was opened.
    var detail: String?
    /// The glyph in the margin (see `Glyph`).
    var glyph = Glyph.dot
    /// Whether it worked. A row that failed is drawn, not hidden — that is
    /// the difference between a record and a brag.
    var failed = false
    /// What the row shows under its title: Dia's own chips. A call carries
    /// what it asked with (the query), and what came back (the results, each
    /// with its site's mark), because "Searched the web" alone says nothing
    /// about what it found.
    var chips: [Chip] = []
}

extension AIToolStep {
    /// One chip on a row: a pill with a 12pt mark and a label — Dia's
    /// `.chip` (11pt, 6/8 padding, a 999 radius, 4% of the ink as its
    /// ground). A site's own mark when there is one, a glyph otherwise.
    struct Chip: Identifiable, Equatable, Codable {
        var id = UUID()
        var label: String
        /// The site whose mark it shows, when it has one.
        var site: String?
        /// Which glyph stands in when there is no mark.
        var glyph: Glyph = .globe
    }
}

extension AIToolStep {
    /// The mark in the margin. Dia maps its tools onto SF Symbols and tints a
    /// picture with `background: currentColor` over a mask, which is what a
    /// template image in AppKit is; `dot` is its 6pt circle for a step with no
    /// tool of its own.
    enum Glyph: String, Codable {
        case dot
        case globe
        case tabs
        case shield
        case cursor
        case page
        case question
        case command
        case stop
    }

    /// The words for a tool that ran, in Dia's grammar: a verb for what
    /// happened, and a count when it happened more than once.
    ///
    /// `times` is how many calls of this tool the turn made in a row, which is
    /// what its "(2 times)" says; `detail` is the one thing worth naming under
    /// it, if any.
    static func named(_ tool: String, times: Int = 1, detail: String? = nil, failed: Bool = false) -> AIToolStep {
        let one = singular(tool)
        let title: String
        var said = detail
        switch tool {
        case "snapshot":
            title = Localized("Read the page")
        case "read":
            title = Localized("Read the page")
        case "screenshot":
            title = Localized("Took a screenshot")
        case "tabs":
            title = Localized("Tabs")
        case "navigate":
            title = Localized("Opened a page")
        case "back":
            title = Localized("Went back")
        case "forward":
            title = Localized("Went forward")
        case "reload":
            title = Localized("Reloaded the page")
        case "click":
            title = Localized("Clicked")
        case "set_value":
            title = Localized("Filled in")
        case "press":
            title = Localized("Pressed a key")
        case "scroll":
            title = Localized("Scrolled")
        case "wait_for":
            title = Localized("Waited")
        case "ask_user":
            title = Localized("Asked you")
        default:
            title = one
        }
        // Dia counts a repeat rather than drawing the same row again.
        if times > 1 { said = Self.times(times) }
        return AIToolStep(kind: .tool, tool: tool, title: title, detail: said,
                          glyph: glyph(tool), failed: failed)
    }

    /// The model's own line while it works: Dia's `activity`, drawn as a dot
    /// with grey words rather than as a tool's row, because nothing has
    /// happened yet — it is what the assistant is doing, not what the browser
    /// did.
    static func note(_ said: String) -> AIToolStep {
        AIToolStep(kind: .note, tool: "say", title: said, detail: nil, glyph: .dot)
    }

    /// The row for a call, with what it carried and what came back as chips:
    /// the address a page was opened on, the page that was read, the query a
    /// search was made with. Dia puts these under its rows and they are most
    /// of what makes the row worth reading.
    static func done(_ tool: String, arguments: AIToolArguments, did: String, failed: Bool) -> AIToolStep {
        // `did` is the audit record, so it is the row's own detail unless
        // something more specific is found below.
        var step = named(tool, detail: did, failed: failed)
        switch tool {
        case "navigate":
            if let url = arguments.string("url") { step.chips = [site(url)] }
        case "tabs":
            if let url = arguments.string("url") { step.chips = [site(url)] }
        case "read", "snapshot":
            // The page it read, by name where the tab has one.
            step.chips = []
        default:
            break
        }
        return step
    }

    /// A site as a chip: its mark, and its own name for itself.
    static func site(_ address: String) -> Chip {
        let host = URL(string: address)?.host() ?? address
        return Chip(label: host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression),
                    site: host, glyph: .globe)
    }

    /// "Searched the web (2 times)": Dia's own way of saying a thing happened
    /// more than once without drawing it twice.
    private static func times(_ count: Int) -> String {
        Localized("\(count) times")
    }

    private static func singular(_ tool: String) -> String {
        switch tool {
        case "snapshot", "read": return Localized("Read the page")
        case "screenshot": return Localized("Took a screenshot")
        case "tabs": return Localized("Tabs")
        case "navigate": return Localized("Opened a page")
        case "back": return Localized("Went back")
        case "forward": return Localized("Went forward")
        case "reload": return Localized("Reloaded the page")
        case "click": return Localized("Clicked")
        case "set_value": return Localized("Filled in")
        case "press": return Localized("Pressed a key")
        case "scroll": return Localized("Scrolled")
        case "wait_for": return Localized("Waited")
        case "ask_user": return Localized("Asked you")
        default: return tool
        }
    }

    private static func glyph(_ tool: String) -> Glyph {
        switch tool {
        case "navigate", "back", "forward", "reload": return .globe
        case "tabs": return .tabs
        case "click", "set_value", "press", "scroll": return .cursor
        case "snapshot", "read", "screenshot": return .page
        case "ask_user": return .question
        case "wait_for": return .command
        default: return .dot
        }
    }
}

// MARK: - the rail

/// The rows of one turn, down a rail on the left — Dia's `.row.ticker-step`
/// on its `--dia-rail`. The line runs behind the markers, and stops with the
/// last one rather than trailing into the answer.
///
/// A finished turn folds them: what is shown is the heading ("Read the page",
/// the count when there were many) and the rows are a click away. Dia folds
/// the same way (`showingAll`), and the reason is the same — a turn that did
/// nine things should not push the answer off the screen.
struct AIToolRail: View {
    let steps: [AIToolStep]
    /// Whether the turn is still going: the rail then grows a row at a time
    /// and ends in the dots, as Dia's does, and does not fold — a turn you are
    /// watching should not hide itself.
    var running = false
    /// Folded once the turn is done, unless someone opened it.
    @State private var open = false

    /// Dia's own numbers, in points, read off its stylesheet: the rail's line
    /// 2 wide and 18 to the left of the text (`--dia-rail-*`), a 16pt marker,
    /// a 6pt dot, and 22 between steps (`--rail-gap`).
    private enum Measure {
        static let center: CGFloat = -18
        static let line: CGFloat = 2
        static let marker: CGFloat = 16
        static let dot: CGFloat = 6
        static let step: CGFloat = 22
        static let spacing: CGFloat = 6
        /// Where the line starts inside a marker, and where it resumes after.
        static var inset: CGFloat { marker / 2 + spacing }
    }

    private var heading: String {
        let tools = steps.filter { $0.kind == .tool }
        guard let first = tools.first else { return Localized("What it did") }
        if tools.count == 1 { return first.title }
        if Set(tools.map(\.tool)).count == 1 { return first.title }
        return Localized("What it did")
    }

    var body: some View {
        if running {
            rows(folded: false)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        // Dia keeps up to three marks in the gutter beside the
                        // heading, one per kind of tool the turn used, so a
                        // folded turn still says what it was made of.
                        gutter
                        Text(verbatim: heading)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.Chat.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.Chat.faint)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open { rows(folded: true).transition(.opacity) }
            }
        }
    }

    /// The marks of a folded turn: Dia's `.icons`, up to three, one per glyph
    /// the turn actually used.
    private var gutter: some View {
        HStack(spacing: 4) {
            ForEach(Array(marks.prefix(3).enumerated()), id: \.offset) { _, glyph in
                Image(systemName: symbol(glyph))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.Chat.faint)
            }
        }
    }

    /// The glyphs of the tool rows, each once, in the order they happened.
    private var marks: [AIToolStep.Glyph] {
        var seen: [AIToolStep.Glyph] = []
        for step in steps where step.kind == .tool && step.glyph != .dot {
            if !seen.contains(step.glyph) { seen.append(step.glyph) }
        }
        return seen
    }

    /// The rows, and — while the turn runs — the dots under them, which is
    /// Dia's waiting pulse at the foot of its rail.
    private func rows(folded: Bool) -> some View {
        VStack(alignment: .leading, spacing: Measure.step) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                row(step, last: index == steps.count - 1, tail: running)
            }
            if running {
                // Dia's `.pending`: the three dots as the next row's body, with
                // the rail run down to them — what is still going, in the
                // column where the next title will appear.
                HStack(alignment: .top, spacing: 10) {
                    ZStack(alignment: .top) {
                        if !steps.isEmpty {
                            Rectangle()
                                .fill(Palette.Chat.edge)
                                .frame(width: Measure.line)
                                .padding(.top, -(Measure.step + Measure.inset))
                                .padding(.bottom, Measure.marker / 2)
                        }
                    }
                    .frame(width: Measure.marker)
                    PendingDots()
                        .padding(.top, 5)
                    Spacer(minLength: 0)
                }
            }
        }
        // Dia fades the last of a folded list into the answer instead of
        // cutting it: its `.bubble.collapsible:not(.expanded)` masks the body
        // from opaque at 70% to almost nothing at the foot.
        .modifier(FadeFoot(on: folded && !running))
    }

    /// Dia's connector: from half a marker plus its spacing, down through the
    /// gap to the next marker.
    private var line: some View {
        Rectangle()
            .fill(Palette.Chat.edge)
            .frame(width: Measure.line)
            .padding(.top, Measure.inset)
            .padding(.bottom, -(Measure.step + Measure.inset))
    }

    private func row(_ step: AIToolStep, last: Bool, tail: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                if !last || tail { line }
                mark(step)
            }
            .frame(width: Measure.marker, alignment: .top)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: step.title)
                    // A note is narration, so it is grey; a tool's row is the
                    // record, so it is a step heavier. Dia's own weights:
                    // `--dia-fw-medium` on the tool title, and thinking at
                    // `--dia-fs-thinking`.
                    .font(.system(size: 13, weight: step.kind == .tool ? .medium : .regular))
                    .foregroundStyle(step.failed ? Palette.unsafe
                                     : step.kind == .tool ? Palette.Chat.muted : Palette.Chat.faint)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = step.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.Chat.faint)
                        .lineLimit(2)
                }
                if !step.chips.isEmpty { chips(step.chips) }
            }
            Spacer(minLength: 0)
        }
    }

    /// Dia's `.chips`: a wrapping row 6 apart, each chip popping in at a
    /// scale of a quarter with its own delay, and a plain "+N more" when the
    /// list is longer than it will show.
    private func chips(_ chips: [AIToolStep.Chip]) -> some View {
        let shown = Array(chips.prefix(3))
        let rest = chips.count - shown.count
        return Flow(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, chip in
                ChipPill(chip: chip, delay: Double(index) * 0.03)
            }
            if rest > 0 {
                Text(verbatim: "+ \(rest) more")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.Chat.faint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private func mark(_ step: AIToolStep) -> some View {
        // A note is Dia's plain dot whatever it says: narration has no icon.
        if step.glyph == .dot || step.kind == .note {
            Circle()
                .fill(step.failed ? Palette.unsafe : Palette.Chat.faint)
                .frame(width: Measure.dot, height: Measure.dot)
                .frame(height: Measure.marker, alignment: .center)
        } else {
            Image(systemName: symbol(step.glyph))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(step.failed ? Palette.unsafe : Palette.Chat.faint)
                .frame(height: Measure.marker, alignment: .center)
        }
    }

    /// Dia's own table (`Zr` in nodes/4.DUxGFY7h.js), tool to SF Symbol.
    private func symbol(_ glyph: AIToolStep.Glyph) -> String {
        switch glyph {
        case .dot: return "circle.fill"
        case .globe: return "globe"
        case .tabs: return "rectangle.split.3x1"
        case .shield: return "shield"
        case .cursor: return "cursorarrow"
        case .page: return "doc.text"
        case .question: return "questionmark.bubble"
        case .command: return "command"
        case .stop: return "stop.circle.fill"
        }
    }
}

/// Dia's `.pending`: three 5pt dots 4pt apart in the gutter, each rising from
/// one to one and a half in `0.8s` and back, a tenth of a second behind the
/// one before it. It is the rail's own "still going", and it lives in the
/// margin where the next mark will be.
private struct PendingDots: View {
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var lit = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.Chat.dot)
                    .frame(width: 5, height: 5)
                    .scaleEffect(lit ? 1.45 : 1)
                    .animation(calm ? nil : .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1), value: lit)
            }
        }
        // Centred on the marker and allowed to be wider than it: Dia's rail
        // lets the dots overrun the gutter rather than shrink them.
        .fixedSize()
        .onAppear { if !calm { lit = true } }
    }
}

/// Dia's fade at the foot of a folded list: opaque to 70%, then almost
/// nothing. It is how a cut list says "there was more" without a second
/// control for it.
private struct FadeFoot: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        content.mask {
            if on {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.7),
                                       .init(color: .black.opacity(0.1), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
    }
}

/// One chip: 11pt, 6/8 padding, a 999 radius over 4% of the ink, a 12pt mark
/// at its left and its label beside it — Dia's `.chip`, down to the mark
/// having no radius of its own and a site's own favicon standing there when it
/// has one.
private struct ChipPill: View {
    let chip: AIToolStep.Chip
    let delay: Double

    @State private var arrived = false

    var body: some View {
        HStack(spacing: 4) {
            mark
                .frame(width: 12, height: 12)
            Text(verbatim: chip.label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.Chat.muted)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous).fill(Palette.Chat.card)
        }
        // `--tool-chip-pop`: a quarter size to one over 0.15s, each a little
        // after the one before it.
        .scaleEffect(arrived ? 1 : 0.25)
        .opacity(arrived ? 1 : 0)
        .animation(.easeOut(duration: 0.15).delay(delay), value: arrived)
        .onAppear { arrived = true }
    }

    @ViewBuilder private var mark: some View {
        // A site's own favicon, drawn the way the tab strip draws it, and a
        // glyph where there is none.
        if let site = chip.site, let address = URL(string: site.hasPrefix("http") ? site : "https://\(site)"),
           let icon = Favicons.shared.cached(for: address) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
        } else {
            Image(systemName: glyph)
                .font(.system(size: 10))
                .foregroundStyle(Palette.Chat.faint)
        }
    }

    private var glyph: String {
        switch chip.glyph {
        case .globe: return "globe"
        case .page: return "doc.text"
        case .cursor: return "cursorarrow"
        case .tabs: return "rectangle.split.3x1"
        case .question: return "questionmark.bubble"
        case .command: return "command"
        case .shield: return "shield"
        case .stop: return "stop.circle.fill"
        case .dot: return "circle.fill"
        }
    }
}

/// Chips wrap, and SwiftUI has no wrapping stack: this lays them out in rows
/// the way Dia's `flex-wrap: wrap` does.
private struct Flow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
