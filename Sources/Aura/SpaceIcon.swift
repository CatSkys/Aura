import AppKit
import SwiftUI

// A space's icon, drawn wherever a space is named: the dot at the foot of
// the column and the one before the tabs, the row of icons a new space picks
// from, and the menus that list the spaces.
//
// Nearly all of them are Apple's own symbols, asked for by name. The first
// in the list is Aura's mark, which is a path rather than a symbol (see
// Logomark in Design.swift), so it is drawn in place of one and tinted like
// the symbols it stands among — one view for both, so a space that wears the
// mark looks the same everywhere, and one picture for the menus, which are
// given images rather than views.

struct SpaceIcon: View {
    /// One of `Spaces.icons`, or any symbol the caller draws for itself (the
    /// plus on the dot while a space is being made).
    var symbol: String
    /// The point size it would be if it were one of Apple's symbols. The mark
    /// is drawn a touch larger: its canvas keeps a margin that a symbol's
    /// glyph hasn't, and a filled shape of the same ink reads lighter than a
    /// drawn one.
    var size: CGFloat
    var weight: Font.Weight = .medium
    var shade: Color = Palette.ink

    var body: some View {
        if symbol == Spaces.mark {
            Logomark()
                .fill(shade, style: FillStyle(eoFill: true))
                .frame(width: size * 1.05, height: size * 1.05)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(shade)
        }
    }

    /// The same as a picture, for the menus, which take an image and not a
    /// view. A template, so AppKit inks it in the row's own colour and its
    /// dark and light looks, as it does a symbol. Sixteen points, which is
    /// what a symbol's own picture comes to, and drawn to its edges: the
    /// mark fills its canvas where a symbol's glyph stands a little inside
    /// one, so the two come to ink of the same height in a menu.
    static func picture(_ symbol: String, size: CGFloat = 16) -> NSImage? {
        guard symbol == Spaces.mark else {
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let fill = NSBezierPath(cgPath: Logomark().path(in: rect).cgPath)
            fill.windingRule = .evenOdd
            NSColor.black.setFill()
            fill.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
