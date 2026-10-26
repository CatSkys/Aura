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
    /// The tool's own account of what it did — AITool's `did`, the audit
    /// record. Kept with the row and not drawn on it: Dia's rail shows a
    /// title and what came back, never the machine's receipt, and a rail of
    /// receipts reads as a log instead of as sentences.
    var audit: String?
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
    /// The mark in the margin. Dia names its glyphs and maps each name to an
    /// SF Symbol (`Zr` in nodes/4.DUxGFY7h.js), tinting a mask with
    /// `currentColor`; AppKit's template images are the same idea. The names
    /// are Dia's own, so the mapping below is a table and not a judgement.
    enum Glyph: String, Codable {
        case dot
        case page
        case globe
        case tabs
        case search
        case edit
        case attach
        case comment
        case contact
        case people
        case commandPrompt
        case stopSolid
        case bubbleQuestion
        case bulletedList
        case backToWindow
        case brain
        case calendar
        case mail
        case bubbles
        case folder
        case pencil
        case person
        case list
        case compress
        case splitView
        case keyboard
        case terminal
        case robot
        case support
    }

    /// A row's title and glyph, from Dia's own table (`Xn` in
    /// chunks/CQThNcLC.js). Every one of its entries is a pair — present
    /// participle while the call is happening, past tense once it is done —
    /// and that is its whole grammar of progress: `X(t, present, past)` picks
    /// one by `complete`. A row in this app is written when the call has
    /// finished, so it says the past tense; the present is here for the row
    /// that is still running.
    ///
    /// Its titles never carry the tool's result. Dia puts what came back in
    /// rows under the title — a query, the pages found, the tab it opened —
    /// because "Read the page" is the statement and "71 elements" is the
    /// result, and mixing them makes a log rather than a sentence.
    static func named(_ tool: String, _ going: Bool = false, where site: String? = nil) -> AIToolStep {
        let (title, glyph) = words(for: tool, going, where: site)
        return AIToolStep(kind: .tool, tool: tool, title: title, detail: nil, glyph: glyph)
    }

    /// Dia's table, for the tools this browser has. Where Dia has no entry
    /// the tool keeps its own name, which is what its `external` case does
    /// with a tool it doesn't know.
    private static func words(for tool: String, _ going: Bool, where site: String?) -> (String, Glyph) {
        switch tool {
        case "read", "snapshot", "screenshot":
            // Dia's `toolResultRead` / `attachmentRead`: the page, by its
            // `page` glyph.
            return (going ? Localized("Reading the page") : Localized("Read the page"), .page)
        case "navigate":
            return (going ? Localized("Opening page") : Localized("Opened page"), .globe)
        case "back":
            return (going ? Localized("Going back") : Localized("Went back"), .globe)
        case "forward":
            return (going ? Localized("Going forward") : Localized("Went forward"), .globe)
        case "reload":
            return (going ? Localized("Reloading page") : Localized("Reloaded page"), .globe)
        case "tabs":
            // Dia's `qn`: one verb per action, in both tenses.
            return (going ? Localized("Working with tabs") : Localized("Worked with tabs"), .tabs)
        case "click":
            return (going ? Localized("Clicking") : Localized("Clicked"), .pencil)
        case "set_value":
            return (going ? Localized("Filling in") : Localized("Filled in"), .keyboard)
        case "press":
            return (going ? Localized("Pressing a key") : Localized("Pressed a key"), .keyboard)
        case "scroll":
            return (going ? Localized("Scrolling") : Localized("Scrolled"), .backToWindow)
        case "wait_for":
            return (going ? Localized("Waiting") : Localized("Waited"), .commandPrompt)
        case "ask_user":
            return (Localized("Asked you"), .bubbleQuestion)
        default:
            return (tool, .support)
        }
    }

    /// The row of a call that has run: title from the table, and under it
    /// what the call carried and came to — Dia's `byline`, its `queries`, and
    /// its `links`.
    static func done(_ tool: String, arguments: AIToolArguments, did: String, failed: Bool) -> AIToolStep {
        var step = named(tool)
        step.failed = failed
        // The row is Dia's: a title, and under it what the call carried or
        // came to as chips. It never prints the tool's own account — "Took a
        // snapshot of the page: 71 elements" is the machine's receipt, and a
        // rail of receipts reads as a log instead of as sentences. The
        // receipt is still the audit record; it goes to the model, not here.
        step.audit = did
        switch tool {
        case "navigate":
            if let url = arguments.string("url") { step.chips = [site(url)] }
        case "tabs":
            if let url = arguments.string("url") { step.chips = [site(url)] }
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

    /// The model's own line while it works: Dia's `activity`, drawn as a dot
    /// with grey words rather than as a tool's row, because nothing has
    /// happened yet — it is what the assistant is doing, not what the browser
    /// did.
    static func note(_ said: String) -> AIToolStep {
        AIToolStep(kind: .note, tool: "say", title: said, detail: nil, glyph: .dot)
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

    /// The folded row's own words, and Dia's: when a turn used one sort of
    /// tool it says that sort in the past — "Searched the web", "Searched
    /// tabs" — and when it used several it says what it gathered, which is
    /// `Gathered context` (`Vr` in nodes/4.DUxGFY7h.js). One call of one tool
    /// keeps its own title, as its rows do.
    private var heading: String {
        let tools = steps.filter { $0.kind == .tool }
        guard let first = tools.first else { return Localized("What it did") }
        if tools.count == 1 { return first.title }
        let kinds = Set(tools.map(kind(_:)))
        if kinds.count == 1, let only = kinds.first { return only.past }
        return Localized("Gathered context")
    }

    /// Dia's own grouping of a tool into what it went and got (`zr`).
    private func kind(_ step: AIToolStep) -> Sort {
        switch step.tool {
        case "navigate", "back", "forward", "reload", "read", "snapshot", "screenshot":
            return .web
        case "tabs":
            return .tabs
        default:
            return .context
        }
    }

    /// The three things a turn can have gone and done, with Dia's past-tense
    /// names for each.
    private enum Sort {
        case web, tabs, context

        var past: String {
            switch self {
            case .web: return Localized("Searched the web")
            case .tabs: return Localized("Searched tabs")
            case .context: return Localized("Gathered context")
            }
        }
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

    /// Dia's connector, and it is a segment per step and not one rule through
    /// them. Its CSS is exact about both ends:
    ///
    ///     top: calc(line-center + connector-inset);
    ///     height: max(0px, calc(100% + rail-gap - 2 * connector-inset));
    ///
    /// with `connector-inset` = half a marker plus `connector-spacing` (8 + 6
    /// = 14) and `rail-gap` 22. Worked through in this file's own points: the
    /// segment starts 22 below the row's top — 6 under its marker — and ends
    /// 16 above the row's bottom, which is 6 above the next row's marker. So
    /// every mark sits in a gap, and the rail reads as a column of short
    /// lines rather than a line behind the marks. Drawn as one line it also
    /// doubled up where the segments met its neighbours, which is what made
    /// some lengths of it darker than others.
    private var line: some View {
        Rectangle()
            .fill(Palette.Chat.edge)
            .frame(width: Measure.line)
            .padding(.top, Measure.marker + Measure.spacing)
            .padding(.bottom, -Measure.marker)
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
                    .modifier(Shimmer(on: running && step.kind == .tool))
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
        .modifier(RowIn())
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
        markBody(step).modifier(MarkerIn())
    }

    @ViewBuilder private func markBody(_ step: AIToolStep) -> some View {
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

    /// Dia's own table (`Zr` in nodes/4.DUxGFY7h.js), glyph name to SF
    /// Symbol — copied, not chosen:
    ///
    ///     brain→brain  alignLeft→align-left  search→search  calendar→calendar
    ///     mail→mail  message/comment→comment  bubbles→bubbles  folder→folder
    ///     page→page  globe→globe  tabs→split-view  pencil→edit
    ///     person→contact  people→people  terminal→command-prompt
    ///     stop→stop-solid  question→bubble-question  list→bulleted-list
    ///     compress→back-to-window  paperclip→attach
    ///
    /// A few names its own table never uses but its tables above do
    /// (`keyboard`, `robot`, `support`) get the closest symbol.
    private func symbol(_ glyph: AIToolStep.Glyph) -> String {
        switch glyph {
        case .dot: return "circle.fill"
        case .brain: return "brain"
        case .search: return "magnifyingglass"
        case .calendar: return "calendar"
        case .mail: return "envelope"
        case .comment, .bubbleQuestion: return "bubble.left"
        case .bubbles: return "bubble.left.and.bubble.right"
        case .folder: return "folder"
        case .page: return "doc.text"
        case .globe: return "globe"
        case .tabs, .splitView: return "rectangle.split.3x1"
        case .pencil, .edit: return "pencil"
        case .person, .contact: return "person.crop.circle"
        case .people: return "person.2"
        case .commandPrompt, .terminal: return "apple.terminal"
        case .stopSolid: return "stop.fill"
        case .bulletedList, .list: return "list.bullet"
        case .backToWindow, .compress: return "arrow.down.right.and.arrow.up.left"
        case .attach: return "paperclip"
        case .keyboard: return "keyboard"
        case .robot: return "gearshape"
        case .support: return "wrench.and.screwdriver"
        }
    }
}

/// Dia's `dia-shimmer`: the words of a row still being written are painted by
/// a gradient that sweeps across them once every 1.5s, in 90 steps, with the
/// middle of the sweep dropped to half strength — `background-clip: text` over
/// a 250%-wide gradient moved from 160% to -60%. It is how its unfinished
/// disclosure titles say "not settled yet" without a spinner.
private struct Shimmer: ViewModifier {
    let on: Bool

    @Environment(\.accessibilityReduceMotion) private var calm

    func body(content: Content) -> some View {
        if on, !calm {
            TimelineView(.animation(minimumInterval: 1.5 / 90)) { context in
                // 90 steps of a 1.5s sweep: where the bright band is now.
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.5) / 1.5
                let at = 160 - 220 * phase
                content
                    .foregroundStyle(
                        LinearGradient(stops: [
                            .init(color: Palette.Chat.muted, location: max(0, (at - 10) / 100)),
                            .init(color: Palette.Chat.muted.opacity(0.45), location: min(1, max(0, at / 100))),
                            .init(color: Palette.Chat.muted, location: min(1, (at + 10) / 100)),
                        ], startPoint: .leading, endPoint: .trailing))
            }
        } else {
            content
        }
    }
}

/// A row arriving while the turn runs: Dia's rows come in from
/// `translateY(6px)` and no opacity (`--reveal`, its empty state's fade-in),
/// and the words resolve with them. Used only while a turn is going, so a
/// finished answer's rail is simply there.
private struct RowIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || calm ? 0 : 6)
            .animation(calm ? nil : .easeOut(duration: 0.22), value: shown)
            .onAppear { shown = true }
    }
}

/// Dia's marker entrance, and the one place it puts a blur: a mark arrives
/// from `opacity 0`, `blur(10px)` and `scale(.2)` over 695.6413353499257ms
/// (`--marker-duration` in nodes/4.DUxGFY7h.js, which is what it measures
/// once and writes into the style), so a new row's mark resolves out of a
/// smudge instead of appearing.
private struct MarkerIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || calm ? 0 : 10)
            .scaleEffect(shown || calm ? 1 : 0.2)
            .animation(calm ? nil : .easeOut(duration: 0.6956), value: shown)
            .onAppear { shown = true }
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
        // Room for the widest the dots get: `scaleEffect` does not change the
        // layout size, so without this the growing dot is drawn against the
        // clip of its own 5pt frame and loses its edge.
        .frame(height: 5 * 1.45)
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
        // A mask clips to its own bounds even when it is solid, so the mask
        // is only ever attached when there is something to fade. Attached
        // always, it cut the growing dots in half at the foot of the rail.
        if on {
            content.mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.7),
                                       .init(color: .black.opacity(0.1), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            content
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
        case .search: return "magnifyingglass"
        case .tabs, .splitView: return "rectangle.split.3x1"
        case .bubbleQuestion: return "bubble.left"
        case .commandPrompt, .terminal: return "apple.terminal"
        case .pencil, .edit: return "pencil"
        case .dot: return "circle.fill"
        default: return "globe"
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
