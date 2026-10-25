import AppKit
import SwiftUI

// The bar along the top of a page while it is coming: Arc's own — a thin grey
// groove with a small dark pill that runs from one end of it to the other and
// back, in the window's own ink.
//
// It keeps to the middle of the page, and to a hand's width: a browser that is
// working says so at the top of what it is working on, and says no more than
// that.
//
// It is layers rather than SwiftUI shapes for the reason the field's breath is
// layers (see Omnibox.swift's Breath): animated by SwiftUI this is drawn again
// on the main thread every frame — 18% of a core with the window doing nothing
// (24 Sep 2026) — where Core Animation plays it in the render server for
// nothing, at whatever the screen does.
//
// The bar is in the page all along and only lit while the page is loading: a
// view put in and taken out again is a view that can be caught halfway through
// arriving (a tab that opens already loading put it there late and it never
// showed), where a layer's opacity has no such middle.

struct Beam: NSViewRepresentable {
    /// Whether the page is still coming.
    var loading: Bool

    /// The groove: Arc's own bar, which is 126 points across and 3½ high,
    /// measured off a window of its own — over the page's middle, and narrowed
    /// to a third of the page where the page is narrower than that.
    static let region: CGFloat = 1.0 / 3
    static let widest: CGFloat = 126
    static let height: CGFloat = 3.5
    /// The pill that runs in it, as a share of it.
    static let pill: CGFloat = 0.28
    /// One run, in seconds: quick enough to read as the browser working rather
    /// than as something drifting past, and eased at both ends — the pill slows
    /// where it turns.
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

/// The view the bar lives in: the groove, and the pill that runs in it.
final class Streak: NSView {
    private let groove = CALayer()
    private let pill = CALayer()
    /// The size the bar was last laid out for, so a layout pass that changed
    /// nothing doesn't put the run back to the start.
    private var laid: CGSize = .zero
    /// The groove's length and the pill's, and how far the pill's middle may
    /// travel from the groove's.
    private var length: CGFloat = 0
    private var mark: CGFloat = 0
    private var lane: CGFloat = 0

    /// Whether the page is coming. Faded, so the bar arrives and goes rather
    /// than blinking.
    var lit = false {
        didSet {
            guard lit != oldValue else { return }
            if lit { run() } else { pill.removeAnimation(forKey: "run") }
            groove.opacity = lit ? 1 : 0
            pill.opacity = lit ? 1 : 0
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in [groove, pill] {
            bar.cornerCurve = .continuous
            bar.opacity = 0
            layer?.addSublayer(bar)
        }
        groove.cornerRadius = Beam.height / 2
        pill.cornerRadius = Beam.height / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Seen, never pressed: a bar over a page cannot take the page's clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The inks are resolved against the window's appearance, so they are set
    /// again whenever that changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        inks()
    }

    /// A layer animation is dropped when the view leaves its window, so the run
    /// is put back each time one arrives.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        inks()
        laid = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laid else { return }
        laid = bounds.size
        length = min(bounds.width * Beam.region, Beam.widest)
        mark = length * Beam.pill
        lane = (length - mark) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Hung from the edge: the groove's top row is the page's top row.
        groove.bounds = CGRect(x: 0, y: 0, width: length, height: Beam.height)
        groove.position = CGPoint(x: bounds.midX, y: bounds.height - Beam.height / 2)
        pill.bounds = CGRect(x: 0, y: 0, width: mark, height: Beam.height)
        pill.position = CGPoint(x: bounds.midX, y: groove.position.y)
        CATransaction.commit()
        inks()
        run()
    }

    /// The groove in the page's faint grey, the pill in its ink — which is what
    /// Arc's bar is: a black mark on a light window, a pale one on a dark.
    private func inks() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            groove.backgroundColor = Palette.NS.faint.cgColor
            pill.backgroundColor = Palette.NS.ink.cgColor
        }
    }

    /// From one end of the groove to the other and back, for as long as the bar
    /// is lit.
    private func run() {
        pill.removeAnimation(forKey: "run")
        guard lit, window != nil, !Motion.reduced, lane > 0 else { return }
        let cross = CABasicAnimation(keyPath: "position.x")
        cross.fromValue = bounds.midX - lane
        cross.toValue = bounds.midX + lane
        cross.duration = Beam.crossing
        cross.autoreverses = true
        cross.repeatCount = .infinity
        cross.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pill.add(cross, forKey: "run")
    }
}
