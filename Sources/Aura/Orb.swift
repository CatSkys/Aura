import SwiftUI

// The sphere the conversation shows while it is working. Dia's: a radial
// gradient with its highlight up and to the left, so it reads as a ball
// rather than a dot, breathing between one size and a size and a half.
//
// Its colour is the thing it is thinking about — the space's theme where
// there is one — so the ball is the window's own, not a decoration laid over
// it. Bring the app back from reduced motion and it holds still at its
// resting size: a pulse nobody asked for is a pulse in the way.

struct Orb: View {
    /// What it is made of. One colour, and the gradient does the rest.
    var seed: Color = .accentColor
    var size: CGFloat = 24
    /// Told apart from the still one by the caller: a reading stream moves,
    /// a finished answer's ball does not.
    var moving = true

    @State private var swell = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        seed.mix(with: .white, by: 0.72),
                        seed,
                        seed.mix(with: .black, by: 0.28),
                    ],
                    center: UnitPoint(x: 0.35, y: 0.30),
                    startRadius: 0,
                    endRadius: size * 0.82
                )
            )
            .frame(width: size, height: size)
            .scaleEffect(swell ? 1.5 : 1)
            .animation(moving && !Motion.reduced
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                       : nil, value: swell)
            .onAppear { if moving, !Motion.reduced { swell = true } }
            .onChange(of: moving) { _, now in swell = now && !Motion.reduced }
            .accessibilityHidden(true)
    }
}

extension Color {
    /// This colour, moved a fraction of the way to another. SwiftUI's own
    /// blend, so a theme colour keeps its hue when it is lightened or
    /// darkened rather than washing out.
    func mix(with other: Color, by amount: Double) -> Color {
        let from = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let to = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let t = max(0, min(1, amount))
        return Color(nsColor: NSColor(
            srgbRed: from.redComponent + (to.redComponent - from.redComponent) * t,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * t,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * t,
            alpha: from.alphaComponent + (to.alphaComponent - from.alphaComponent) * t
        ))
    }
}
