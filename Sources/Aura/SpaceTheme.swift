import AppKit

/// A space's colour, as Arc's Space Style Editor keeps one: a hue, how much of
/// it there is, and how much grain lies over the window's glass. One theme
/// gives both appearances — pale in a light window, deep in a dark one — the
/// way Arc's `WindowTheme` carries a light and a dark semantic palette from a
/// single seed (see `arc-rea/REPORT.md` §2–3).
///
/// The bands the two tints are made in are Arc's own, read off its spaces:
/// `tintedLight` keeps 2–9% saturation near 97% brightness, `shadedDark` 53–88%
/// near 50%, and the dark window background is that darkened to about 16%.
/// Aura keeps one number — how saturated the space is — and slides along those
/// bands with it, which is enough to tell one space's sidebar from another's
/// without ever making the rows unreadable.
struct SpaceTheme: Codable, Equatable {
    /// 0–360.
    var hue: Double
    /// 0–100: how much of the hue shows, from a grey to Arc's drab page.
    var sat: Double
    /// 0–100: how light the colour it came from was. Arc's own window
    /// backgrounds sit in bands — 97% in a light window, about 16% in a dark
    /// one — and the shades inside each band follow this: without it the nine
    /// greys were nine names for one glass.
    var value: Double
    /// 0–100: the grain over the glass (Arc's `intensityFactor`).
    var grain: Double

    /// Arc's spaces sit around a third of the way up its noise slider.
    static let grainDefault: Double = 35
    /// A colour with no lightness of its own: the middle of the band.
    static let valueDefault: Double = 62

    init(hue: Double, sat: Double, value: Double = SpaceTheme.valueDefault,
         grain: Double = SpaceTheme.grainDefault) {
        self.hue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        self.sat = min(max(sat, 0), 100)
        self.value = min(max(value, 0), 100)
        self.grain = min(max(grain, 0), 100)
    }

    /// A colour picked anywhere — Arc's presets, the system's colour panel, one
    /// of Aura's old six — as the hue, saturation and lightness a space wears.
    init(colour: NSColor) {
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.init(hue: Double(h) * 360, sat: Double(s) * 100, value: Double(b) * 100)
    }

    init(hex: UInt32) {
        self.init(colour: NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        ))
    }

    /// A space coloured before there was a `value` in the file reads as the
    /// middle of the band, which is where the old glass was.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hue = (try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0)
        sat = try container.decodeIfPresent(Double.self, forKey: .sat) ?? 0
        value = try container.decodeIfPresent(Double.self, forKey: .value) ?? Self.valueDefault
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? Self.grainDefault
    }
}

/// What a theme looks like on the window, and the colours Arc offers to start
/// from.
enum SpacePalette {
    /// The glass's own tint in a light window: Arc's `tintedLight`, pale enough
    /// that black rows read on it and the desktop still shows through. The
    /// shade follows the colour's own lightness inside the band, so a white
    /// preset and a black one are not the same glass.
    static func light(_ theme: SpaceTheme) -> NSColor {
        let s = theme.sat / 100, v = theme.value / 100
        return NSColor(hue: theme.hue / 360, saturation: 0.02 + 0.07 * s,
                       brightness: 0.84 + 0.14 * v, alpha: 1)
    }

    /// The same in a dark window: Arc's dark background, `shadedDark` taken
    /// down to the band's own shade, holding light rows.
    static func dark(_ theme: SpaceTheme) -> NSColor {
        let s = theme.sat / 100, v = theme.value / 100
        // A grey stays grey: with no saturation asked for, none is invented.
        let presence = min(1, s / 0.05)
        return NSColor(hue: theme.hue / 360, saturation: presence * (0.30 + 0.50 * s),
                       brightness: 0.09 + 0.17 * v, alpha: 1)
    }

    /// How much grain the theme asks for, over the glass.
    static func grain(_ theme: SpaceTheme) -> CGFloat {
        0.02 + CGFloat(theme.grain / 100) * 0.10
    }

    /// The sidebar's own inks over that tint, as Arc's semantic palette gives
    /// each theme its title and secondary colours: near-black and steeped in
    /// the space's hue on the pale glass, near-white and barely hued on the
    /// deep one (Arc's light title #2A141B, its dark one #EEE3E6).
    static func title(_ theme: SpaceTheme, dark: Bool) -> NSColor {
        let s = theme.sat / 100
        return dark
            ? NSColor(hue: theme.hue / 360, saturation: 0.02 + 0.10 * s, brightness: 0.96, alpha: 1)
            : NSColor(hue: theme.hue / 360, saturation: 0.05 + 0.55 * s, brightness: 0.16, alpha: 1)
    }

    /// What a row's icon and a quiet sentence wear: darker than Aura's own
    /// greys on the pale glass, where a 55% grey left the hint under a tab
    /// hard to read.
    static func secondary(_ theme: SpaceTheme, dark: Bool) -> NSColor {
        let s = theme.sat / 100
        return dark
            ? NSColor(hue: theme.hue / 360, saturation: 0.03 + 0.12 * s, brightness: 0.72, alpha: 1)
            : NSColor(hue: theme.hue / 360, saturation: 0.04 + 0.40 * s, brightness: 0.40, alpha: 1)
    }

    /// The quietest step: a placeholder, a disabled line.
    static func tertiary(_ theme: SpaceTheme, dark: Bool) -> NSColor {
        let s = theme.sat / 100
        return dark
            ? NSColor(hue: theme.hue / 360, saturation: 0.04 + 0.14 * s, brightness: 0.54, alpha: 1)
            : NSColor(hue: theme.hue / 360, saturation: 0.03 + 0.30 * s, brightness: 0.55, alpha: 1)
    }

    /// The space's colour as it can be seen on the page: what the light along a
    /// page's top edge wears while the page is coming (see Beam.swift).
    ///
    /// Neither of the column's own colours will do there. The title is a
    /// near-black only a hair off the hue — over white it reads as ink, not as
    /// a colour — and the glass is a wash pale enough to vanish on the page's
    /// white. So the hue is deepened to where it shows. A grey stays grey, as
    /// in `dark`: with no saturation asked for, none is invented.
    static func glow(_ theme: SpaceTheme, dark: Bool) -> NSColor {
        let s = theme.sat / 100
        let presence = min(1, s / 0.05)
        return NSColor(hue: theme.hue / 360, saturation: presence * (0.08 + 0.60 * s),
                       brightness: dark ? 0.86 : 0.55, alpha: 1)
    }

    /// Arc's 27: three pages of nine in its Space Style Editor, read off the
    /// asset catalog (`arc-rea/REPORT.md` §5). 柔和 / 沉稳 / 灰阶.
    static let pastel: [UInt32] = [
        0xFDFBFA, 0xFBEAF3, 0xECD2EA, 0xF7CDD2, 0xFAE1D5, 0xFEF9E7, 0xE4FCEC, 0xE0F2FB, 0xC5C6E2,
    ]
    static let drab: [UInt32] = [
        0x4B3B58, 0x623856, 0x854444, 0xA77048, 0xD1B46A, 0xCDCCA8, 0x84A885, 0x34604B, 0x2D4468,
    ]
    static let greys: [UInt32] = [
        0xFFFFFF, 0xE5E5E5, 0xCCCCCC, 0xB2B2B2, 0x808080, 0x666666, 0x333333, 0x1A1A1A, 0x000000,
    ]

    /// One swatch's colour, for the sheet.
    static func swatch(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
