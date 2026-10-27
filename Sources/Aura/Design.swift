import SwiftUI
import AppKit

// Lifted from Office Inspiration, with the ground turned white: there the work
// floats on an off-white canvas, here the page *is* the ground and everything
// the browser draws has to get out of its way.
//
// Every colour is a pair — one for a light window, one for a dark — and
// resolves itself against whatever appearance the window has. The window
// takes its appearance from the app, and the app from Settings › Appearance:
// light, dark, or whatever the Mac is doing. Nothing else in the code knows
// which it is.
enum Palette {
    static let ground = Color(nsColor: NS.ground)
    static let ink = Color(nsColor: NS.ink)             // neutral-900 · neutral-100
    static let muted = Color(nsColor: NS.muted)         // neutral-500
    static let faint = Color(nsColor: NS.faint)         // neutral-300 · neutral-700
    static let hairline = Color(nsColor: NS.hairline)   // neutral-200 · neutral-800
    static let wash = Color(nsColor: NS.wash)           // the live tab
    /// The live pin: among squares that already wear a faint grey, the one
    /// you are on stands out from them as a live row does from the white.
    static let pinLive = Color(nsColor: NS.pinLive)
    static let hover = Color(nsColor: NS.hover)         // the one under the pointer
    /// The fill a card takes where it used to take a hairline round its edge:
    /// a step off the window's ground, so a page reads as blocks of colour
    /// rather than as boxes, and the tiles, fields and pictures inside it
    /// keep the greys they already had.
    static let card = Color(nsColor: NS.card)
    /// A row on one of those cards, under the pointer or the one Find lit:
    /// ink laid over the card rather than a grey of its own, so it shows as
    /// much on a card as on the ground, in both appearances.
    static let rowHover = Color(nsColor: NS.ink).opacity(0.045)
    /// The row the keys are on in the command bar's list, and the row under
    /// the pointer: one grey, since the two never show at once — the pointer
    /// takes the mark over the moment it is on a row. Deep enough to be a
    /// block of its own rather than a hint of one.
    static let pick = Color(nsColor: NS.pick)
    /// Around the page's card, with the tabs down the side: the column, the
    /// bookmarks bar and the gaps share it, a touch off the page's white, so
    /// the card reads as one (see CardEdge).
    static let frame = Color(nsColor: NS.frame)
    /// The column's own greys, on that ground: the live tab, the one under the
    /// pointer, the resting pin squares and the live pin. The white column's
    /// wash, hover and pinLive all but vanished on it (Drice: the pins' squares
    /// and the open tab no longer showed), so these keep the same steps of
    /// contrast from the frame that those kept from the white.
    static let sideWash = Color(nsColor: NS.sideWash)
    static let sideHover = Color(nsColor: NS.sideHover)
    static let sideTile = Color(nsColor: NS.sideTile)
    static let sidePinLive = Color(nsColor: NS.sidePinLive)
    /// The disc a sideways swipe brings in (see Stage's Disc): one dark disc
    /// with a white arrow on it, dark in both appearances as Arc's is. It is a
    /// thing over the page rather than part of the page's own greys, and the
    /// pages it covers are as often dark as light — a page's own ink would be
    /// white on one and black on the next.
    static let swipeDisc = Color.black.opacity(0.82)
    /// The arrow on it, and the cross where letting go would close.
    static let swipeGlyph = Color.white

    /// The colours a setting's icon tile wears: rows are told apart by colour
    /// before their symbol is read, as Arc's own settings are. One to a group,
    /// and no group on one page wearing another's (see SettingsIndex.tint), so
    /// the palette has to be at least as wide as the longest page. The
    /// system's own, which keep their strength in both appearances, with a
    /// white symbol on top.
    static let tileBlue = Color(nsColor: .systemBlue)
    static let tileTeal = Color(nsColor: .systemTeal)
    static let tileGreen = Color(nsColor: .systemGreen)
    static let tileIndigo = Color(nsColor: .systemIndigo)
    static let tilePurple = Color(nsColor: .systemPurple)
    static let tilePink = Color(nsColor: .systemPink)
    static let tileOrange = Color(nsColor: .systemOrange)
    static let tileRed = Color(nsColor: .systemRed)

    /// The only two that aren't grey: a connection nobody can read on the
    /// way, and one anybody can (see SiteCard.swift).
    static let safe = Color(nsColor: NS.safe)           // green-700 · green-400
    static let unsafe = Color(nsColor: NS.unsafe)       // amber-700 · amber-400

    /// The same colours for the AppKit corners of the app — a text field's
    /// ink, a window's background — which want an NSColor and keep it.
    enum NS {
        static let ground = pair(1.0, 0.11)
        static let ink = pair(0.09, 0.93)
        static let muted = pair(0.55, 0.58)
        static let faint = pair(0.83, 0.32)
        static let hairline = pair(0.91, 0.20)
        static let wash = pair(0.937, 0.175)
        static let pinLive = pair(0.90, 0.21)
        static let hover = pair(0.965, 0.15)
        static let card = pair(0.966, 0.155)
        static let pick = pair(0.90, 0.20)
        static let frame = pair(0.955, 0.075)
        static let sideWash = pair(0.895, 0.155)
        static let sideHover = pair(0.915, 0.13)
        static let sideTile = pair(0.925, 0.115)
        static let sidePinLive = pair(0.86, 0.19)
        /// The conversation's own surface (see `Palette.Chat`): Dia's values,
        /// not the page's. Its ground is a step darker than the paper the
        /// browser draws on, and what you write on sits on white above it.
        static let chatSurface = pair(0.953, 0.125)
        static let chatRaised = pair(1.0, 0.173)
        static let chatCard = pair(0.977, 0.204)
        static let chatEdge = pair(0.89, 0.275)
        static let chatInk = pair(0.145, 0.882)
        static let chatMuted = pair(0.60, 0.62)
        static let chatFaint = pair(0.70, 0.41)
        /// Dia's waiting dots: 18% of the ink, and 30% at the top of a beat
        /// (`--dot-color` / `--dot-emphasized-color`). Far lighter than any
        /// grey in the column — at `chatFaint` they read as three full stops.
        static let chatDot = pair(0.82, 0.82)
        /// The same three dots on a tab row, which are not the same colour:
        /// Dia draws those at `#c7c7c7` with a `#aaa` top of the beat
        /// (`.dots.tab`), because a row's ground is darker than the column's.
        static let tabDot = pair(0.78, 0.28)
        static let tabDotPulse = pair(0.67, 0.39)

        /// The resting traffic lights, drawn by hand when the app is behind.
        static let resting = pair(0.80, 0.30)
        static let safe = tint(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = tint(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        private static func tint(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(name: nil) { appearance in
                let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: dim ? dark : light, alpha: 1)
            }
        }
    }
}

extension Palette {
    /// The conversation's colours, taken from Dia's own values because the
    /// conversation is Dia's: a surface a step darker than the page, what you
    /// write raised to white on it, and its own ink — softer than the
    /// browser's near-black, which is what makes the panel read as a letter
    /// rather than a dialog.
    enum Chat {
        static let surface = Color(nsColor: NS.chatSurface)
        static let raised = Color(nsColor: NS.chatRaised)
        static let card = Color(nsColor: NS.chatCard)
        static let edge = Color(nsColor: NS.chatEdge)
        static let ink = Color(nsColor: NS.chatInk)
        static let muted = Color(nsColor: NS.chatMuted)
        static let faint = Color(nsColor: NS.chatFaint)
        /// The waiting dots, lighter than any text: Dia draws them at 18% of
        /// the ink and they are meant to be barely there.
        static let dot = Color(nsColor: NS.chatDot)
        /// The waiting dots on a tab row (see AIToolStep's `TabDots`).
        static let tabDot = Color(nsColor: NS.tabDot)
        static let tabDotPulse = Color(nsColor: NS.tabDotPulse)
    }
}

/// The greys of the column's rows, pins and buttons, for the ground they lie
/// on: the white's (the strip, a panel, the column with the page edge to
/// edge) or the window's beside the page's card, set by the column for
/// what is in it (see SideBar.onFrame). Read through the environment, so a
/// row, a pin or a door is the same view on either ground.
struct Greys {
    let wash: Color
    let hover: Color
    let tile: Color
    let pinLive: Color

    static let white = Greys(wash: Palette.wash, hover: Palette.hover,
                             tile: Palette.wash.opacity(0.55), pinLive: Palette.pinLive)
    static let frame = Greys(wash: Palette.sideWash, hover: Palette.sideHover,
                             tile: Palette.sideTile, pinLive: Palette.sidePinLive)
    /// On the window's glass (see Glass.swift): the same steps of contrast,
    /// taken from the window's ink at a few percent rather than from a grey
    /// of its own — a solid grey square laid over the desktop reads as a chip
    /// of paint, and a wash of ink reads the same on light glass and on dark.
    static let glass = Greys(wash: Palette.ink.opacity(0.12), hover: Palette.ink.opacity(0.07),
                             tile: Palette.ink.opacity(0.06), pinLive: Palette.ink.opacity(0.16))
}

private struct GreysKey: EnvironmentKey {
    static let defaultValue = Greys.white
}

extension EnvironmentValues {
    var greys: Greys {
        get { self[GreysKey.self] }
        set { self[GreysKey.self] = newValue }
    }
}

/// The column's own inks for the ground it is on. On the window's glass the
/// ground is the space's colour, so the inks are the space's too — Arc's
/// semantic palette gives each theme a title and secondary colour rather than
/// one grey for every window (see SpaceTheme.swift). Read through the
/// environment, as `Greys` is, so a row, a pin or a door takes them wherever
/// it is in the column.
struct SideInk {
    let ink: Color
    let muted: Color
    let faint: Color

    static let standard = SideInk(ink: Palette.ink, muted: Palette.muted, faint: Palette.faint)

    static func glass(_ theme: SpaceTheme, dark: Bool) -> SideInk {
        SideInk(ink: Color(nsColor: SpacePalette.title(theme, dark: dark)),
                muted: Color(nsColor: SpacePalette.secondary(theme, dark: dark)),
                faint: Color(nsColor: SpacePalette.tertiary(theme, dark: dark)))
    }
}

private struct SideInkKey: EnvironmentKey {
    static let defaultValue = SideInk.standard
}

extension EnvironmentValues {
    var sideInk: SideInk {
        get { self[SideInkKey.self] }
        set { self[SideInkKey.self] = newValue }
    }
}

/// Light, dark, or the Mac's own — the one choice that colours everything.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// What the app is told to be. Nothing, for "system": the app then
    /// follows the Mac, and changes with it.
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// Set on the app rather than on the window, so every panel, alert and
    /// sheet — and every page, which follows the window it is in — agrees.
    ///
    /// Never from inside whatever is happening when it is asked for: the
    /// switch in Settings changes it from within an animation, over a panel
    /// in transition, and re-skinning every window in the middle of that is
    /// how a window ends up with a layer that takes clicks and shows
    /// nothing. The next turn of the run loop is soon enough.
    func apply() {
        let wanted = appearance
        DispatchQueue.main.async {
            guard NSApp.appearance !== wanted, NSApp.appearance?.name != wanted?.name else { return }
            NSApp.appearance = wanted
        }
    }
}

enum Metrics {
    /// The tab strip. The window's title bar is grown to match it so the
    /// traffic lights come down with the tabs — otherwise giving the row room
    /// to breathe just leaves it sitting below three buttons it used to line
    /// up with.
    static let strip: CGFloat = 52
    /// With the tabs down the side the page is a card: this far from the
    /// window's edges (and from the column, folded away), and its corners
    /// this round.
    static let cardGap: CGFloat = 8
    static let cardRadius: CGFloat = 10
    /// Where the first tab starts. The traffic lights run from 19 to 79 —
    /// measured, not guessed — so this leaves them the same air on their right
    /// that the window gives them on their left.
    static let lights: CGFloat = 100
    /// Back, forward and reload, at the far end of the row beside the
    /// bookmarks: three doors and the air before the next one.
    static let helm: CGFloat = 3 * 26 + 2 * 2 + 8
    /// The same three doors again, in the sidebar, where they sit right of
    /// the lights instead. The column already has 10 of horizontal padding
    /// of its own before this even starts. 72 put the back door's box 3
    /// points from the zoom button and its chevron 12, "a little tight"
    /// (feedback, 22 Oct 2026): at 80 the chevron is 20 points clear of the
    /// lights, about the 19 the window leaves on their left, as a toolbar's
    /// first item sits in Safari. A column too narrow for that gives back
    /// what it must (SideBar.lights), down to where it was.
    static let sideLights: CGFloat = 80
    /// The three doors' own width, without the air after them.
    static let helmDoors: CGFloat = 3 * 26 + 2 * 4
    /// The band left at the top when there is no strip: just enough for the
    /// traffic lights to sit in, and nothing else.
    static let bare: CGFloat = 34
    /// Tabs are a fixed width rather than the width of their titles, so the
    /// cross always lands in the same place and the row never rearranges
    /// itself while you read it. They give way when there are too many:
    /// narrower than tabTitled they show their site's mark alone, and they
    /// stop at tabMinWidth, the mark and its air. Past that the row scrolls,
    /// inside its own edges.
    static let tabWidth: CGFloat = 186
    static let tabTitled: CGFloat = 80
    static let tabMinWidth: CGFloat = 36
    static let tabGap: CGFloat = 2
    /// A pinned tab is a square the height of the row, holding one letter.
    static let pinWidth: CGFloat = 30
    /// The square at the end of the row that opens a new page.
    static let plusWidth: CGFloat = 30
    /// The address field, in both the places it shows up.
    static let fieldWidth: CGFloat = 560
    /// The column of titles down the left, in the way that has one.
    static let side: CGFloat = 232
    static let sideMin: CGFloat = 176
    static let sideMax: CGFloat = 440
}

// One spring for anything that moves between two places, one for anything that
// arrives or leaves. Using the same two everywhere is most of why a thing feels
// like a single piece of software rather than a pile of views.
// When macOS Reduce Motion is on in System Settings, transitions become
// immediate so the interface does not jump or slide.
enum Motion {
    /// Whether interface transitions should be immediate, following the
    /// Mac's own accessibility setting.
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Whether the Mac is short of power: Low Power Mode is on, or it is hot
    /// enough that macOS is holding its processors back. Then the two springs
    /// below become a short ease-out. A spring keeps moving long after it
    /// looks done: glide takes about 0.5 s to settle, 30 frames that SwiftUI
    /// works out one by one on the main thread, which is the thread a busy or
    /// slowed Mac takes time from first, and every frame it misses shows as a
    /// stutter. 0.16 s is 10 frames, and is over before a missed one shows.
    /// Read at the moment something moves, so it follows the switch at once.
    /// Only once it is turned on in Settings › General (Preferences.lightMotion).
    static var light: Bool {
        guard Store.settings.bool(forKey: lightKey) else { return false }
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    nonisolated static let lightKey = "motion.light"

    static var glide: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    static var settle: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .spring(response: 0.30, dampingFraction: 0.86)
    }

    static var quick: Animation? {
        reduced ? nil : .easeOut(duration: 0.14)
    }

    // MARK: - What a press does

    // Arc's own numbers, read out of its binary rather than guessed: of the
    // 128 springs it writes inline, half are underdamped — 0.28/0.63 and
    // 0.30/0.60 most often — and its easings cluster on 0.10–0.18 s. So a
    // press goes down on an easing, because the answer has to be instant, and
    // comes back on an underdamped spring, because that is the part you feel.
    // Anything damped all the way, as glide and settle are, reads as
    // "finished" rather than as "released".

    /// Going down: quick, and with nothing to overshoot — the click is
    /// answered on the frame it happens.
    static var pressed: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.10) : .easeOut(duration: 0.12)
    }

    /// Coming back up: Arc's most used spring, a little past where it lands.
    static var released: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .spring(response: 0.28, dampingFraction: 0.63)
    }

    /// On and off — a switch's knob, a segment's pill. Softer than a press
    /// (0.25/0.70), since a knob travels rather than snaps.
    static var toggled: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .spring(response: 0.25, dampingFraction: 0.70)
    }

    /// A thing picked out of a row of them, as Stage's swipe disc lands: quick,
    /// and damped all the way, since two frames of bounce on a thumbnail reads
    /// as a glitch rather than as weight.
    static var picked: Animation? {
        reduced ? nil : .spring(response: 0.22, dampingFraction: 0.9)
    }

    /// A thing crossing from one plain state to another (a colour, a shadow,
    /// a glyph): no travel, so no spring, and short.
    static var crossfade: Animation? {
        reduced ? nil : .easeOut(duration: 0.12)
    }

    /// Something that will not move, saying so: the field that shivers.
    static var refuse: Animation? {
        reduced ? nil : .easeOut(duration: 0.5)
    }

    /// A move that is neither a spring nor a crossfade, at the length its
    /// place was tuned for: an entering page's cover, a pull, a meter. The
    /// same easing Aura has always used there, now with the two ways of
    /// turning motion off actually applied — Reduce Motion, and Low Power
    /// Mode, which is what `light` is for.
    static func ease(_ duration: Double) -> Animation? {
        reduced ? nil : light ? .easeOut(duration: min(duration, 0.16)) : .easeOut(duration: duration)
    }

    /// The same, for the moves eased at both ends.
    static func easeBoth(_ duration: Double) -> Animation? {
        reduced ? nil : light ? .easeOut(duration: min(duration, 0.16)) : .easeInOut(duration: duration)
    }

    /// How far a tab gives while it is pressed (see Give): enough to feel
    /// under the pointer, about 3 points on a pill and 7 on a column row.
    static let give: CGFloat = 0.97

    /// And how far a button gives (see Press): a pill, a door, a capsule in
    /// Settings — the things that answer a click rather than carry a drag.
    /// Pressing a button is most of what there is to do in Aura, and until
    /// now it answered in colour alone.
    static let dip: CGFloat = 0.96

    /// The small square icons — a door in the row, a tool in Extensions —
    /// give a little further, since a shape that small needs it to be seen.
    static let dipSmall: CGFloat = 0.92

    /// Whether anything at all gives under the press (Settings › Tabs › Press
    /// feedback). Read where something is pressed, so it follows the switch
    /// without a restart. On unless turned off, and a choice already stored
    /// stands either way.
    static var presses: Bool {
        (Store.settings.object(forKey: pressKey) as? Bool) ?? true
    }

    nonisolated static let pressKey = "tabs.give"

    /// The folded column or strip coming out over the page, and going back.
    /// On glide it was slow both ways, next to Arc and Dia timed frame by
    /// frame on the same Mac: each slides its sidebar 90% of the way out in
    /// about 95ms and back in about 70ms, where glide took over 200ms. Coming
    /// out lands with a little weight behind it — about nine points of
    /// overshoot on a full column — so the card reads as arriving rather than
    /// as pushed out of the edge; going in is damped all the way, since
    /// nothing is arriving to settle. Fold.slide moves the window's buttons on
    /// the same numbers, in Core Animation's terms.
    static func fold(out: Bool) -> (response: Double, damping: Double) {
        out ? (0.30, 0.72) : (0.15, 1)
    }

    static func folding(out: Bool) -> Animation? {
        let spring = fold(out: out)
        return reduced ? nil : .spring(response: spring.response, dampingFraction: spring.damping)
    }
}

/// Aura's mark — a pebble with a hole in it, as the designer drew it, read
/// from its own path data rather than loaded from a file, so it stays a crisp
/// vector at any size. No plate, no square behind it: the mark draws exactly
/// what the source file has and nothing it doesn't, the way every other icon
/// in this app is a bare shape rather than a shape on a background. The one
/// exception is the macOS app icon, which needs an opaque square whether the
/// mark wants one or not — that's the Dock's requirement, not the logo's, and
/// Icon/AppIcon.png is that square.
struct Logomark: Shape {
    /// The mark's own canvas, from Icon/mark.svg (see Tools/mark.py).
    static let canvas = AuraMark.canvas

    /// The path itself: absolute M, L, C, Z, as Tools/mark.py writes it.
    private static let data = AuraMark.data

    func path(in rect: CGRect) -> Path {
        // Fit the canvas into whatever frame this is given, centred, at the
        // larger scale that still keeps it inside — an SVG viewBox's "meet".
        let scale = min(rect.width / Logomark.canvas.width, rect.height / Logomark.canvas.height)
        let ox = rect.midX - Logomark.canvas.width * scale / 2
        let oy = rect.midY - Logomark.canvas.height * scale / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        var path = Path()
        var last = CGPoint.zero
        var start = CGPoint.zero
        for (c, n) in Logomark.commands {
            switch c {
            case "M": last = CGPoint(x: n[0], y: n[1]); start = last; path.move(to: pt(n[0], n[1]))
            case "L": last = CGPoint(x: n[0], y: n[1]); path.addLine(to: pt(n[0], n[1]))
            case "H": last.x = n[0]; path.addLine(to: pt(last.x, last.y))
            case "V": last.y = n[0]; path.addLine(to: pt(last.x, last.y))
            case "C":
                var k = 0
                while k + 5 < n.count {
                    path.addCurve(to: pt(n[k + 4], n[k + 5]), control1: pt(n[k], n[k + 1]), control2: pt(n[k + 2], n[k + 3]))
                    last = CGPoint(x: n[k + 4], y: n[k + 5])
                    k += 6
                }
            case "Z": path.closeSubpath(); last = start
            default: break
            }
        }
        return path
    }

    /// Read once. Absolute M, L, H, V, C, Z — what Figma writes for a
    /// flattened shape, and nothing else is needed.
    private static let commands: [(Character, [CGFloat])] = {
        var out: [(Character, [CGFloat])] = []
        var current: Character?
        var numbers: [CGFloat] = []
        var token = ""
        func flush() {
            if !token.isEmpty, let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        for ch in data {
            if "MLHVCZ".contains(ch) {
                flush()
                if let current { out.append((current, numbers)) }
                current = ch
                numbers = []
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" && !token.isEmpty {
                flush()
                token = "-"
            } else {
                token.append(ch)
            }
        }
        flush()
        if let current { out.append((current, numbers)) }
        return out
    }()
}

/// Wrong address, said without a dialog: the field shivers and stops.
struct Shake: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard !Motion.reduced else { return ProjectionTransform(.identity) }
        // Three there-and-backs, tapering to nothing, so it settles rather than
        // stopping mid-swing.
        let decay = 1 - travel
        return ProjectionTransform(
            CGAffineTransform(translationX: sin(travel * .pi * 6) * 7 * decay, y: 0)
        )
    }
}

extension View {
    /// What a popover holds, on the ground colour. From macOS 26 a popover
    /// clips what it holds to its own rounded glass; before, an opaque
    /// background was drawn out to the content's square edges, past the
    /// popover's rounded corners (macOS 15, by email). There the popover is
    /// handed the colour and fills its own shape with it, arrow included.
    /// `card`: drawn as its own rounded card, with an edge, on macOS 26.
    func popoverGround(card: Bool = false) -> some View {
        modifier(PopoverGround(card: card))
    }
}

private struct PopoverGround: ViewModifier {
    let card: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if card {
                content
                    .background(Palette.ground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            } else {
                content.background(Palette.ground)
            }
        } else {
            content.presentationBackground(Palette.ground)
        }
    }
}

/// The page as a card in the window, with the tabs down the side: round
/// corners, a hairline edge and a soft shadow under it. The shadow is drawn
/// by a shape behind the page, never by the page's own layers, which would
/// make WebKit's drawing go through it; the page's view is rounded by its own
/// layer as well (see StageView), since a web view is AppKit's and a clip of
/// SwiftUI's is not always carried down to it. Two pages side by side are a
/// card each, drawn by the stage that holds them (see PaneStage).
struct CardEdge: ViewModifier {
    let on: Bool

    // One shape of view, on or off: a page whose view were rebuilt as the
    // card comes and goes (the tabs across the top, a video taking the
    // screen) would be handed to a new stage just as WebKit takes it to its
    // full screen window. Off, the clip reaches far past the page and cuts
    // nothing, and the edge and shadow are clear.
    func body(content: Content) -> some View {
        content
            .clipShape(CardShape(on: on))
            .background {
                CardShape(on: on)
                    .fill(on ? Palette.ground : .clear)
                    .shadow(color: .black.opacity(on ? CardEdge.shadow : 0), radius: 6, y: 1)
            }
            .overlay {
                CardShape(on: on)
                    .strokeBorder(Color.primary.opacity(on ? CardEdge.edge : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    /// How dark the shadow and the edge are, for the stage's own cards too.
    static let shadow: Double = 0.07
    static let edge: Double = 0.08
}

/// The card's outline: round at its corners, or, off, a rectangle reaching
/// far past the page on every side.
private struct CardShape: InsettableShape {
    let on: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        guard on else { return Path(rect.insetBy(dx: -10_000, dy: -10_000)) }
        return RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> CardShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}
