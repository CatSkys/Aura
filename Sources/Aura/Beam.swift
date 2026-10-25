import AppKit
import SwiftUI

// The bar along the top of a page while it is coming: Arc's own — a short,
// rounded streak in the colour Arc's loading page wears, crossing one way and
// back, with a little of its own light around it.
//
// It keeps to the middle third of the page: a browser that is working says so
// at the top of what it is working on, not across the whole of it.
//
// It is a layer rather than a SwiftUI shape for the reason the field's breath
// is a layer (see Omnibox.swift's Breath): animated by SwiftUI this is drawn
// again on the main thread every frame — 18% of a core with the window doing
// nothing (24 Sep 2026) — where Core Animation plays it in the render server
// for nothing, at whatever the screen does.
//
// The bar is in the page all along and only lit while the page is loading: a
// view put in and taken out again is a view that can be caught halfway through
// arriving (a tab that opens already loading put it there late and it never
// showed), where a layer's opacity has no such middle.

struct Beam: NSViewRepresentable {
    /// Whether the page is still coming.
    var loading: Bool

    /// The whole of what the bar touches: a third of the page's width, over its
    /// middle, and never more of the page than that.
    static let region: CGFloat = 1.0 / 3
    /// The bar itself, as a share of that region. Short, so that it has the rest
    /// of the third to travel in.
    static let bar: CGFloat = 0.3
    static let height: CGFloat = 3
    /// How far the bar's own light reaches past it, and how much of it there is.
    static let glow: CGFloat = 7
    static let wash: Swift.Float = 0.55
    /// One crossing, in seconds: quick enough to read as the browser working
    /// rather than as something drifting past, and eased at both ends — the bar
    /// slows where it turns.
    static let crossing: CFTimeInterval = 0.9

    func makeNSView(context: Context) -> Streak { Streak() }

    func updateNSView(_ view: Streak, context: Context) { view.lit = loading }

    /// The room the page was given and no more: it is drawn over the page, and
    /// must not ask for a size of its own.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Streak, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// The view the bar lives in: one layer, and the light it sheds.
final class Streak: NSView {
    private let bar = CALayer()
    /// The size the bar was last laid out for, so a layout pass that changed
    /// nothing doesn't put the crossing back to the start.
    private var laid: CGSize = .zero
    /// The bar's length at that size, and how far its middle may travel either
    /// side of the page's middle.
    private var reach: CGFloat = 0
    private var lane: CGFloat = 0

    /// Whether the page is coming. Faded, so the bar arrives and goes rather
    /// than blinking.
    var lit = false {
        didSet {
            guard lit != oldValue else { return }
            if lit { carry() } else { bar.removeAnimation(forKey: "carry") }
            bar.opacity = lit ? 1 : 0
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bar.cornerRadius = Beam.height / 2
        bar.cornerCurve = .continuous
        bar.shadowOpacity = Beam.wash
        bar.shadowOffset = .zero
        bar.shadowRadius = Beam.glow
        bar.opacity = 0
        layer?.addSublayer(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Seen, never pressed: a bar over a page cannot take the page's clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The colour is resolved against the window's appearance, so it is set
    /// again whenever that changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colour()
    }

    /// A layer animation is dropped when the view leaves its window, so the
    /// crossing is put back each time one arrives.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        colour()
        laid = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laid else { return }
        laid = bounds.size
        // The middle third of the page, with the bar's own length taken out of
        // it: what is left is the room its middle may travel in, so the bar
        // never leaves that third. On a card the round corners stay well clear
        // of it.
        let region = bounds.width * Beam.region
        reach = region * Beam.bar
        lane = (region - reach) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.bounds = CGRect(x: 0, y: 0, width: reach, height: Beam.height)
        // Hung from the edge: its top row is the page's top row.
        bar.position = CGPoint(x: bounds.midX, y: bounds.height - Beam.height / 2)
        bar.shadowPath = CGPath(roundedRect: bar.bounds,
                                cornerWidth: Beam.height / 2, cornerHeight: Beam.height / 2,
                                transform: nil)
        CATransaction.commit()
        colour()
        carry()
    }

    /// Arc's own colour for this, and the light it sheds: the same blue, dimmed.
    private func colour() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let blue = Palette.NS.loading
            bar.backgroundColor = blue.cgColor
            bar.shadowColor = blue.cgColor
        }
    }

    /// Across the middle third and back, for as long as the bar is lit.
    private func carry() {
        bar.removeAnimation(forKey: "carry")
        guard lit, window != nil, !Motion.reduced, lane > 0 else { return }
        let cross = CABasicAnimation(keyPath: "position.x")
        cross.fromValue = bounds.midX - lane
        cross.toValue = bounds.midX + lane
        cross.duration = Beam.crossing
        cross.autoreverses = true
        cross.repeatCount = .infinity
        cross.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bar.add(cross, forKey: "carry")
    }
}
