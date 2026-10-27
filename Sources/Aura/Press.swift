import SwiftUI

// The answer to a click, in one place.
//
// Aura's buttons used to answer in colour alone: the pointer went in, the
// ground changed, and nothing under the hand moved — `.buttonStyle(.plain)`
// draws no press of its own, so fifty-five buttons had none. Arc answers in
// both (its binary writes a spring at 128 places and half of them are
// underdamped); this is that, in the two shapes Aura needs.
//
// `Press` is the ButtonStyle, for anything that is a `Button`: a pill in
// Settings, a door in the row, a capsule in a panel. `Pressed` is for the rows
// that are not buttons at all — they carry a tap over their whole width — and
// it watches the press the way a tab's is watched (see TabPress), so a drag
// over the row is not held up waiting for a click to be ruled out.
//
// Both go down on an easing and come back on a spring (see Motion.pressed and
// Motion.released), both do nothing at all with Reduce Motion on, and both
// defer to Settings › Tabs › Press feedback, which is on unless turned off.

/// A button that gives under the press.
struct Press: ButtonStyle {
    /// How far: Motion.dip for a pill or a capsule, Motion.dipSmall for a
    /// square the size of a door.
    var dip: CGFloat = Motion.dip

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed && Motion.presses && !Motion.reduced
        configuration.label
            .scaleEffect(down ? dip : 1)
            .animation(down ? Motion.pressed : Motion.released, value: down)
    }
}

/// A row or a card that carries a tap rather than a Button, and gives under
/// the press just the same.
struct Pressed: ViewModifier {
    var dip: CGFloat = Motion.give

    @State private var down = false

    /// How far the hand may go before this gives way to whatever the row is
    /// inside — a list that scrolls, a drag that carries it. TabPress keeps
    /// the same four points for the same reason: a press that never fails
    /// keeps the drag waiting until it does, and the row then jumps to its
    /// place on the release instead of following the hand.
    private static let travel: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .scaleEffect(down && !Motion.reduced ? dip : 1)
            .animation(down ? Motion.pressed : Motion.released, value: down)
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: Pressed.travel,
                                pressing: { if Motion.presses { down = $0 } }, perform: {})
    }
}

extension View {
    /// For a row, a card, a swatch: anything pressed with a tap of its own.
    func pressable(_ dip: CGFloat = Motion.give) -> some View {
        modifier(Pressed(dip: dip))
    }
}
