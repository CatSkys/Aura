import SwiftUI

/// Arc's Space Style Editor, kept small: a hue and how much of it, how solid
/// the window's ground is, Arc's 27 colours to start from, and how much grain
/// lies over the glass.
///
/// It is a page of the card the space's dot opens (see SpaceSwitcher), which
/// is a popover, so the column beside it is the preview: every drag writes the
/// space's theme and the window's glass follows (`ContentView` → `WindowGlass`).
/// Arc's own picker is a ring of hues with a slider for how strongly the space
/// takes it; this is the same two numbers as a pad, which needs no dial to
/// explain itself — drawn from the palette itself, so the pad is the colours
/// the column will wear rather than a rainbow that turns to near-white.
struct SpaceThemeEditor: View {
    @ObservedObject var browser: Browser
    @Environment(\.colorScheme) private var scheme

    private var theme: SpaceTheme { browser.space.spaceTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Colour")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(browser.space.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            pad
            groups
            dial("Opacity", \.opacity)
            dial("Grain", \.grain)
            HStack {
                Spacer()
                Button("Reset") { set(nil) }
                    .font(.system(size: 11.5))
            }
        }
        .padding(14)
    }

    // MARK: - the pad

    /// Hue across, how much of it down: the colour with none of itself at the
    /// top, as much as the band holds at the bottom. Dragging anywhere sets
    /// both, as the ring and the slider do in Arc's own editor.
    private var pad: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            ZStack(alignment: .topLeading) {
                // One column per step of hue, each running from no colour to
                // all of it: the same colours the column will wear, in the
                // lightness the space already has.
                HStack(spacing: 0) {
                    ForEach(0..<Pad.hues, id: \.self) { step in
                        let hue = Double(step) / Double(Pad.hues) * 360
                        LinearGradient(
                            colors: [ground(hue: hue, sat: 0), ground(hue: hue, sat: 100)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                Circle()
                    .fill(ground(hue: theme.hue, sat: theme.sat))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.32), radius: 2)
                    .frame(width: 16, height: 16)
                    .position(x: min(max(theme.hue / 360, 0), 1) * width,
                              y: min(max(theme.sat / 100, 0), 1) * height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var next = theme
                        next.hue = min(max(value.location.x / width, 0), 1) * 360
                        next.sat = min(max(value.location.y / height, 0), 1) * 100
                        set(next)
                    }
            )
        }
        .frame(height: 124)
    }

    private enum Pad {
        /// Steps of hue across the pad. Fine enough that a drag reads as one
        /// unbroken colour, and few enough to be 36 gradients drawn once.
        static let hues = 36
    }

    /// The colour the window's ground wears for a point on the pad: the
    /// palette's own answer, in this window's appearance, so what is under the
    /// pointer is what the column beside it turns into.
    private func ground(hue: Double, sat: Double) -> Color {
        var probe = theme
        probe.hue = hue
        probe.sat = sat
        return Color(nsColor: scheme == .dark ? SpacePalette.dark(probe) : SpacePalette.light(probe))
    }

    // MARK: - Arc's colours

    private var groups: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("Pastel", SpacePalette.pastel)
            row("Drab", SpacePalette.drab)
            row("Greyscale", SpacePalette.greys)
        }
    }

    private func row(_ name: LocalizedStringKey, _ hexes: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 4), count: 9), spacing: 4) {
                ForEach(hexes, id: \.self) { hex in
                    swatch(hex)
                }
            }
        }
    }

    private func swatch(_ hex: UInt32) -> some View {
        let colour = SpacePalette.swatch(hex)
        let chosen = matches(hex)
        return Circle()
            .fill(Color(nsColor: colour))
            .frame(width: 24, height: 24)
            .overlay {
                Circle().strokeBorder(chosen ? Palette.ink.opacity(0.85) : Palette.hairline,
                                      lineWidth: chosen ? 2 : 1)
            }
            .contentShape(Circle())
            .onTapGesture {
                var next = SpaceTheme(hex: hex)
                next.grain = theme.grain
                next.opacity = theme.opacity
                set(next)
            }
            .help(String(format: "#%06X", hex))
    }

    /// Whether the space already wears this swatch: the same hue, about the
    /// same amount of it, and the same shade — the nine greys share a hue and
    /// a saturation, so the shade is what tells them apart, and a space with
    /// no colour in it at all has no hue to be wrong about. A picked preset
    /// keeps its grain and its solidity, so it lands exactly.
    private func matches(_ hex: UInt32) -> Bool {
        let preset = SpaceTheme(hex: hex)
        let around = abs(theme.hue - preset.hue)
        let sameHue = theme.sat < 0.5 || min(around, 360 - around) < 1.5
        return sameHue
            && abs(theme.sat - preset.sat) < 1.5
            && abs(theme.value - preset.value) < 1.5
    }

    // MARK: - the two numbers under the colours

    /// A slider for one of the theme's own numbers, labelled on the left by the
    /// name it is asked for by.
    private func dial(_ name: LocalizedStringKey, _ key: WritableKeyPath<SpaceTheme, Double>) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)
                .frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { theme[keyPath: key] }, set: { value in
                var next = theme
                next[keyPath: key] = value
                set(next)
            }), in: 0...100)
            .controlSize(.small)
        }
    }

    /// Through the window, which keeps the list and writes it (see
    /// `Browser.setSpaceTheme`): a theme set on the list here alone was the
    /// window's until it was quit, and gone at the next launch unless
    /// something else happened to save the list on the way.
    private func set(_ next: SpaceTheme?) {
        browser.setSpaceTheme(browser.spaceID, to: next)
    }
}
