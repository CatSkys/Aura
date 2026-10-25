import AppKit
import SwiftUI

// The light along the top edge of a page while it is coming: a streak of the
// window's ink that fades out to both sides — and down into the page, so what
// you see is a glow thrown off the edge rather than a rule drawn under it —
// crossing one way and back for as long as the page is still loading. It keeps
// to the middle third of the page: a browser that is working says so at the top
// of what it is working on, not across the whole of it.
//
// Arc's page shows a bar running along its top while it loads. This is the same
// promise said in light instead of a rule, and it is the field's own breath
// grown a tail (see Omnibox.swift's Breath): one colour — the space's own,
// where the window is wearing one, so a space's pages load in that space's
// light (see SpacePalette.glow) — dark on a light window and pale on a dark
// one, and it hugs the edge without drawing anything a page could take for its
// own content.
//
// It is layers rather than SwiftUI shapes for the reason the breath is layers:
// animated by SwiftUI this is drawn again on the main thread every frame — 18%
// of a core with the window doing nothing (24 Sep 2026) — where Core Animation
// plays it in the render server for nothing, at whatever the screen does.
//
// The fade down is a gradient laid over the streak, not a shadow of it: a
// shadow of a layer this thin is all but invisible next to the streak itself,
// and where it does show it smears as far sideways as down. Two gradients make
// the light fall away in the two directions it has to, and nothing else.
//
// The light is in the page all along and only lit while the page is loading: a
// view put in and taken out again is a view that can be caught halfway through
// arriving (a tab that opens already loading put it there late and it never
// showed), where a layer's opacity has no such middle.

struct Beam: NSViewRepresentable {
    /// Whether the page is still coming.
    var loading: Bool
    /// What colour the light is: the space's own where the window is wearing
    /// it, the window's ink everywhere else (see SpacePalette.glow).
    var tint: Color

    /// The whole of what the light touches: a third of the page's width, over
    /// its middle, and never more of the page than that.
    static let region: CGFloat = 1.0 / 3
    /// The streak itself, as a share of that region. Half of it, so the light
    /// has the other half of the third to travel in.
    static let streak: CGFloat = 0.5
    /// How far the light falls into the page.
    static let height: CGFloat = 22
    /// How much of the ink shows where the light meets the edge; it fades to
    /// nothing at the bottom of `height`.
    static let core: CGFloat = 0.55
    /// One crossing, in seconds: quick enough to read as the browser working
    /// rather than as something drifting past, and eased at both ends — the
    /// light slows where it turns.
    static let crossing: CFTimeInterval = 0.9

    func makeNSView(context: Context) -> Streak { Streak() }

    func updateNSView(_ view: Streak, context: Context) {
        view.lit = loading
        view.tint = tint
    }

    /// The room the page was given and no more: it is drawn over the page, and
    /// must not ask for a size of its own.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Streak, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// The view the light lives in: a streak across the edge, and the fall of it.
final class Streak: NSView {
    private let light = CAGradientLayer()
    private let fall = CAGradientLayer()
    /// The size the light was last laid out for, so a layout pass that changed
    /// nothing doesn't put the crossing back to the start.
    private var laid: CGSize = .zero
    /// The colour the light is, and the one it is told to be.
    var tint: Color = Palette.ink {
        didSet { guard tint != oldValue else { return }; ink() }
    }
    /// The streak's length at that size, and how far its middle may travel
    /// either side of the page's middle.
    private var reach: CGFloat = 0
    private var lane: CGFloat = 0

    /// Whether the page is coming. Faded, so the light arrives and goes rather
    /// than blinking.
    var lit = false {
        didSet {
            guard lit != oldValue else { return }
            if lit { carry() } else { light.removeAnimation(forKey: "carry") }
            light.opacity = lit ? 1 : 0
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Across: nothing at either end, so the light has no beginning to see.
        light.startPoint = CGPoint(x: 0, y: 0.5)
        light.endPoint = CGPoint(x: 1, y: 0.5)
        light.locations = [0, 0.25, 0.75, 1]
        // Down: brightest where it meets the edge, nothing at its foot. A
        // layer's own y runs up from the bottom, and so does this.
        fall.startPoint = CGPoint(x: 0.5, y: 1)
        fall.endPoint = CGPoint(x: 0.5, y: 0)
        fall.locations = [0, 0.35, 1]
        light.mask = fall
        light.opacity = 0
        layer?.addSublayer(light)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Seen, never pressed: a light over a page cannot take the page's clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The ink is the look's: dark on a light window, light on a dark one.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        ink()
    }

    /// A layer animation is dropped when the view leaves its window, so the
    /// crossing is put back each time one arrives.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ink()
        laid = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laid else { return }
        laid = bounds.size
        // The middle third of the page, with the light's own length taken out
        // of it: what is left is the room its middle may travel in, so the
        // light never leaves that third. On a card the round corners stay well
        // clear of it.
        let region = bounds.width * Beam.region
        reach = region * Beam.streak
        lane = (region - reach) / 2
        let size = CGSize(width: reach, height: Beam.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        light.bounds = CGRect(origin: .zero, size: size)
        // Hung from the edge: its top row is the page's top row, and the light
        // falls away from there into the page.
        light.position = CGPoint(x: bounds.midX, y: bounds.height - Beam.height / 2)
        fall.bounds = light.bounds
        fall.position = CGPoint(x: reach / 2, y: Beam.height / 2)
        CATransaction.commit()
        ink()
        carry()
    }

    /// The streak and its fall, in the window's own ink.
    private func ink() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let ink = NSColor(tint)
            light.colors = [ink.withAlphaComponent(0).cgColor,
                            ink.withAlphaComponent(Beam.core).cgColor,
                            ink.withAlphaComponent(Beam.core).cgColor,
                            ink.withAlphaComponent(0).cgColor]
            // A mask reads alpha alone, so the colour it falls from is nothing.
            fall.colors = [ink.withAlphaComponent(1).cgColor,
                           ink.withAlphaComponent(0.55).cgColor,
                           ink.withAlphaComponent(0).cgColor]
        }
    }

    /// Across the middle third and back, for as long as the light is lit.
    private func carry() {
        light.removeAnimation(forKey: "carry")
        guard lit, window != nil, !Motion.reduced, lane > 0 else { return }
        let cross = CABasicAnimation(keyPath: "position.x")
        cross.fromValue = bounds.midX - lane
        cross.toValue = bounds.midX + lane
        cross.duration = Beam.crossing
        cross.autoreverses = true
        cross.repeatCount = .infinity
        cross.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        light.add(cross, forKey: "carry")
    }
}
