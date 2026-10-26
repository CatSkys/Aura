import SwiftUI

/// Arc's Space Style Editor, kept small: a hue and how much of it, Arc's 27
/// colours to start from, and how much grain lies over the glass.
///
/// It is a page of the card the space's dot opens (see SpaceSwitcher), which
/// is a popover, so the column beside it is the preview: every drag
/// writes the space's theme and the window's glass follows (`ContentView`
/// → `WindowGlass`). Arc's own picker is a ring of hues with a slider for how
/// strongly the space takes it; this is the same two numbers as a pad, which
/// needs no dial to explain itself.
struct SpaceThemeEditor: View {
    @ObservedObject var browser: Browser

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
            HStack(spacing: 8) {
                Text("Grain")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 34, alignment: .leading)
                Slider(value: Binding(get: { theme.grain }, set: { grain in
                    var next = theme
                    next.grain = grain
                    set(next)
                }), in: 0...100)
                .controlSize(.small)
            }
            HStack {
                Spacer()
                Button("Reset") { set(nil) }
                    .font(.system(size: 11.5))
            }
        }
        .padding(14)
    }

    // MARK: - the pad

    /// Hue across, how much of it down: white at the top, Arc's drab page at
    /// the bottom. Dragging anywhere sets both, as the ring and the slider do
    /// in Arc's own editor.
    private var pad: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 0.85, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(Color(hue: theme.hue / 360, saturation: theme.sat / 100, brightness: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.28), radius: 2)
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
                set(next)
            }
            .help(String(format: "#%06X", hex))
    }

    /// Whether the space already wears this swatch: the same hue, about the
    /// same amount of it, and the same shade — the nine greys share a hue and
    /// a saturation, so the shade is what tells them apart. A picked preset
    /// keeps its grain, so it lands exactly.
    private func matches(_ hex: UInt32) -> Bool {
        let preset = SpaceTheme(hex: hex)
        let around = abs(theme.hue - preset.hue)
        return min(around, 360 - around) < 1.5
            && abs(theme.sat - preset.sat) < 1.5
            && abs(theme.value - preset.value) < 1.5
    }

    /// Through the window, which keeps the list and writes it (see
    /// `Browser.setSpaceTheme`): a theme set on the list here alone was the
    /// window's until it was quit, and gone at the next launch unless
    /// something else happened to save the list on the way.
    private func set(_ next: SpaceTheme?) {
        browser.setSpaceTheme(browser.spaceID, to: next)
    }
}
