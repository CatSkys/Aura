import AppKit

/// The window's own bottom: glass, wherever the window paints nothing.
///
/// The column of tabs and the frame the page's card sits on used to be a
/// colour of their own — `Palette.frame` over a window as opaque as paper.
/// They are glass now, the way DeepDive's sidebar is: the column paints no
/// ground at all (`SideBar`), nor does the bookmarks bar or the window's own
/// `window_`, so what shows through them is the desktop, blurred.
///
/// Two recipes, one per macOS: `NSGlassEffectView` on 26 and later — the
/// system's liquid glass, tinted toward near-black or white — and
/// `NSVisualEffectView`'s sidebar vibrancy before it, tinted more firmly
/// because that material is paler than glass. Both sample what lies behind
/// the *window*, so the window itself has to be see-through; `WindowGlass.lay`
/// makes it so, and the page's card stays the one opaque thing in the window.
///
/// The window's glass is tinted with the space's own colour (see
/// SpaceTheme.swift) and carries a whisper of grain — Arc's window background,
/// which is a gradient and a texture tinted by the space's theme
/// (`WindowTheme`'s `intensityFactor`, `overlay`: grain, sand, denim, tweed),
/// rather than a clean sheet of blur.
final class GlassBacking: NSView {
    /// The system's liquid glass, on 26 and later; nil before it, where the
    /// vibrancy view below carries the window instead.
    private let glass: NSView?
    private let material = NSVisualEffectView()
    private let tint = NSView()
    /// The grain over the lot (see `Grain`).
    private let grain = Grain()
    /// The space on screen's colour, if it has one of its own (see
    /// `setSpaceTheme`). Nil before a space's theme arrives, and for a window
    /// with no space: the neutral grey then.
    private var theme: SpaceTheme?

    /// Over liquid glass: it carries brightness of its own, so the tint only
    /// pulls it toward a colour of the window's own. Lifted from DeepDive's
    /// recipe, then made firmer and less white here. DeepDive tints its bright
    /// glass with pure white; over a pale wallpaper that is a sheet of light
    /// (user, on the first build: "有点太透", then "有点太曝"), and the column
    /// came out lighter than the page beside it. Arc's window background is
    /// the other way round — a near-white *grey* wash, around 92%, faintly
    /// tinted by the space, always a shade darker than the page (`WindowTheme`
    /// semantic palette: background #F3ECEF beside a #FFFFFF page). So: a
    /// neutral light grey, opaque enough to hold the wallpaper's colours down
    /// to a suggestion. Stronger and the sidebar is a flat plate again.
    private static let darkGlassTint = NSColor(srgbRed: 14 / 255, green: 14 / 255, blue: 16 / 255, alpha: 0.76)
    private static let lightGlassTint = NSColor(srgbRed: 0.918, green: 0.918, blue: 0.929, alpha: 0.82)
    /// Over the vibrancy material: paler than glass, and wants a firmer hand.
    private static let darkTint = NSColor(srgbRed: 14 / 255, green: 14 / 255, blue: 16 / 255, alpha: 0.84)
    private static let lightTint = NSColor(srgbRed: 0.918, green: 0.918, blue: 0.929, alpha: 0.86)
    /// A themed tint is Arc's own background: opaque enough to read as the
    /// window's material, with the desktop still moving behind it.
    private static let themedLight: CGFloat = 0.85
    private static let themedDark: CGFloat = 0.82
    /// The grain a window with no theme wears — the neutral glass's whisper.
    private static let lightGrain: CGFloat = 0.05
    private static let darkGrain: CGFloat = 0.07

    override init(frame: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            // The window's own corners cut the glass: AppKit's window shape
            // does that, and a second radius here would draw a rim inside it.
            glass.cornerRadius = 0
            self.glass = glass
        } else {
            self.glass = nil
        }
        super.init(frame: frame)
        if let glass {
            fill(glass)
        } else {
            material.material = .sidebar
            material.blendingMode = .behindWindow
            // Alive behind an inactive window too: dropped to the resting
            // state it renders as dead grey, which reads as "this window is
            // not the one" even when it is.
            material.state = .active
            fill(material)
            tint.wantsLayer = true
            fill(tint)
        }
        fill(grain)
        applyTint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Nowhere to click: the glass is the window's ground, not a control.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Light or dark with the app (Settings › Appearance sets `NSApp.appearance`,
    /// which every window follows): liquid glass takes a new `tintColor`, the
    /// vibrancy branch a new wash over its material, and the grain the strength
    /// that goes with the look.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    /// The space on screen's colour: the glass takes it as its own tint, pale
    /// in a light window and deep in a dark one, and the grain takes the
    /// strength the space asked for (`ContentView.washGlass`).
    func setSpaceTheme(_ theme: SpaceTheme?) {
        self.theme = theme
        applyTint()
    }

    private func applyTint() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var colour: NSColor
        if let theme {
            colour = (dark ? SpacePalette.dark(theme) : SpacePalette.light(theme))
                .withAlphaComponent(dark ? Self.themedDark : Self.themedLight)
        } else {
            colour = dark ? Self.darkTint : Self.lightTint
        }
        if #available(macOS 26.0, *), let glass = glass as? NSGlassEffectView {
            glass.tintColor = colour
        } else {
            tint.layer?.backgroundColor = colour.cgColor
        }
        grain.alphaValue = theme.map { SpacePalette.grain($0) } ?? (dark ? Self.darkGrain : Self.lightGrain)
    }

    /// Laid to the window's bounds, and kept there as the window resizes.
    private func fill(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}

/// The grain over the glass: a very faint noise, so the material reads as
/// paper rather than as a clean sheet. Arc lays one of four textures over its
/// window background (grain, sand, denim, tweed, at a strength of the space's
/// choosing); this is the quietest of them, fixed, because the column is small
/// next to a window and a texture with a name would invite tuning.
///
/// One 64-point tile, drawn as a pattern wherever the view is: a screenful
/// costs one image draw, and the tile is made once for the app.
private final class Grain: NSView {
    private static let tile: NSImage = {
        let side = 128
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ), let data = rep.bitmapData else { return NSImage(size: NSSize(width: 64, height: 64)) }
        // A fixed seed: the same grain every launch, and no arc4random for
        // something nobody will compare from one run to the next.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for y in 0..<side {
            for x in 0..<side {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                let value = UInt8(truncatingIfNeeded: seed >> 56)
                let pixel = data + (y * side + x) * 4
                pixel[0] = value
                pixel[1] = value
                pixel[2] = value
                pixel[3] = 255
            }
        }
        // 128 pixels over 64 points: a crisp tile on a Retina screen, and a
        // half-size one on any other, where it cannot be told from noise.
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(rep)
        return image
    }()

    override func draw(_ dirtyRect: NSRect) {
        NSColor(patternImage: Self.tile).setFill()
        dirtyRect.fill()
    }

    /// Resized with the window: the pattern is drawn for the new bounds.
    override func layout() {
        super.layout()
        needsDisplay = true
    }
}

/// Where the window's glass is laid, and once only.
@MainActor
enum WindowGlass {
    /// The glass under everything the window draws.
    ///
    /// The window has to be see-through for any of it to be seen — vibrancy
    /// and liquid glass both sample what is behind the window, and an opaque
    /// window leaves them a flat grey to blend with. Made once per window and
    /// found again by kind: a window laid twice would be two blurs deep.
    static func lay(in window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        guard let content = window.contentView, let frame = content.superview else { return }
        if let back = frame.subviews.first(where: { $0 is GlassBacking }) as? GlassBacking {
            back.frame = frame.bounds
            return
        }
        let back = GlassBacking(frame: frame.bounds)
        back.autoresizingMask = [.width, .height]
        frame.addSubview(back, positioned: .below, relativeTo: content)
    }

    /// The space on screen's colour, on the window's glass. Nothing to do
    /// when the window isn't up yet: `ContentView.dress` asks again.
    static func setSpaceTheme(_ theme: SpaceTheme?, in window: NSWindow?) {
        guard let window, let content = window.contentView, let frame = content.superview,
              let back = frame.subviews.first(where: { $0 is GlassBacking }) as? GlassBacking
        else { return }
        back.setSpaceTheme(theme)
    }
}
