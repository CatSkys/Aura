import CoreGraphics
import Foundation

// The page following the fingers when a sideways swipe has nowhere to go, and
// going home when they let go: Chromium's elastic overscroll, with Chromium's
// own numbers.
//
// Read from Chromium's source rather than guessed (BSD-3-Clause):
//   third_party/blink/renderer/platform/widget/input/
//     elastic_overscroll_controller.cc
//     elastic_overscroll_controller_exponential.cc
// The exponential one is what a Mac gets — Windows is handed the Bezier one,
// whose numbers are different (kBounceBackMillisecondsPerPixel and the like) —
// so its constants are the ones below.
//
// While the fingers are down the page moves a twentieth of what they travel
// past the edge, and not at all until they are ten points past it. On non-OS
// Android builds Chromium lets a scroller overscroll even where it has nothing
// to scroll (kOverscrollNonScrollableDirection), which is the whole point here:
// a page that cannot go sideways still leans.
//
// Let go and it goes home on Chromium's own curve,
//
//     stretch(t) = (s + v·t·amplitude) · exp(-t·stiffness/period)
//
// a decay of exp(-t·12.5), so under a point within a third of a second — which
// is what `settles` gives SwiftUI as the length of the way back. SwiftUI is not
// handed the curve itself: an eased run of that length reads the same at this
// size, and a spring that disagreed with the pull would be the thing you
// noticed.

enum Elastic {
    /// How far the fingers go for one point of page: kRubberbandStiffness, 20
    /// — a 300-point pull moves the page 15.
    static let stiffness: CGFloat = 20
    /// Nothing moves until they are this far past the edge:
    /// kRubberbandMinimumRequiredDeltaBeforeStretch.
    static let reaches: CGFloat = 10
    /// The two other numbers in the way home: kRubberbandAmplitude and
    /// kRubberbandPeriod.
    static let amplitude: Double = 0.31
    static let period: Double = 1.6
    /// An event later than this after the one before it is a new throw rather
    /// than a continuation, so its velocity stops counting:
    /// kScrollVelocityZeroingTimeout.
    static let zeroing: Double = 0.10

    /// How far the page has leaned, given how far the fingers have gone past
    /// the edge. Chromium's controller has no ceiling of its own; this one has
    /// the page's own width, so a long pull cannot throw it clean off.
    static func stretch(_ accumulated: CGFloat, in width: CGFloat) -> CGFloat {
        let lean = max(0, accumulated - reaches) / stiffness
        return min(lean, max(width, 0) / 3)
    }

    /// How long the way home takes: the decay above, run until there is less
    /// than a point left, and no longer than a moment whatever the pull.
    static func settles(from stretch: CGFloat) -> Double {
        let lean = max(abs(Double(stretch)), 1)
        return min(0.6, period / Double(stiffness) * log(lean) + 0.12)
    }
}
