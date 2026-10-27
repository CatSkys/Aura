import XCTest
@testable import Aura

/// What a space's colour turns into on the window, where it can be read rather
/// than looked at: the column's ground is a pale band (see SpaceTheme.swift),
/// and a space asked for white has to come out white in it.
final class SpaceThemeTests: XCTestCase {
    private func sRGB(_ colour: NSColor) -> NSColor {
        colour.usingColorSpace(.sRGB) ?? colour
    }

    private func saturation(_ colour: NSColor) -> CGFloat { sRGB(colour).saturationComponent }

    func testWhiteIsWhiteInBothWindows() {
        for dark in [false, true] {
            let theme = SpaceTheme(hex: 0xFFFFFF)
            let ground = sRGB(dark ? SpacePalette.dark(theme) : SpacePalette.light(theme))
            XCTAssertEqual(ground.saturationComponent, 0, accuracy: 0.001,
                           "a white space wears no hue at all")
            XCTAssertEqual(ground.redComponent, ground.greenComponent, accuracy: 0.001)
            XCTAssertEqual(ground.greenComponent, ground.blueComponent, accuracy: 0.001)
        }
    }

    func testNoColourAsksForNoHueFromAnyDirection() {
        for hue in stride(from: 0.0, to: 360, by: 45) {
            let theme = SpaceTheme(hue: hue, sat: 0, value: 60)
            for dark in [false, true] {
                XCTAssertEqual(saturation(dark ? SpacePalette.dark(theme) : SpacePalette.light(theme)), 0,
                               accuracy: 0.001, "hue \(hue) invented a colour where none was asked for")
            }
            for ink in [SpacePalette.title(theme, dark: true), SpacePalette.title(theme, dark: false),
                        SpacePalette.secondary(theme, dark: false), SpacePalette.tertiary(theme, dark: false)] {
                XCTAssertEqual(saturation(ink), 0, accuracy: 0.001, "an ink kept a hue of its own")
            }
        }
    }

    func testTheDeepPresetsAreStillPaleInALightWindow() {
        // Arc shows a deep space as a pale colour in a light window (see the
        // bands in SpaceTheme.swift): the hue has to arrive, and not as ink.
        let ground = sRGB(SpacePalette.light(SpaceTheme(hex: 0x4B3B58)))
        XCTAssertGreaterThan(ground.saturationComponent, 0.05, "Arc's deep purple came out as paper")
        XCTAssertLessThan(ground.saturationComponent, 0.20, "…and not as a plate of purple")
        XCTAssertGreaterThan(ground.brightnessComponent, 0.8, "a light window keeps its pale band")
    }

    func testHowSolidTheGroundIsIsTheSpacesOwnNumber() {
        let solid = SpaceTheme(hue: 200, sat: 60, value: 90, grain: 20, opacity: 100)
        let glassy = SpaceTheme(hue: 200, sat: 60, value: 90, grain: 20, opacity: 0)
        XCTAssertEqual(solid.opacity, 100)
        XCTAssertEqual(glassy.opacity, 0)
        XCTAssertEqual(SpaceTheme(hue: 0, sat: 0).opacity, SpaceTheme.opacityDefault)
        XCTAssertEqual(SpaceTheme(hue: 0, sat: 0, opacity: 400).opacity, 100, "clamped like the rest")
    }

    func testAThemeFromBeforeTheGroundCouldBeMadeSolidReadsAsTheOldGlass() throws {
        let json = #"{"hue": 200, "sat": 40, "value": 80, "grain": 50}"#
        let theme = try JSONDecoder().decode(SpaceTheme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.opacity, SpaceTheme.opacityDefault)
        XCTAssertEqual(theme.grain, 50, "the rest of it is the file's own")
    }

    func testAThemeSurvivesBeingWrittenDown() throws {
        let theme = SpaceTheme(hue: 315, sat: 26, value: 35, grain: 70, opacity: 40)
        let back = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(theme))
        XCTAssertEqual(back, theme)
    }

    func testAPresetKeepsItsOwnHueAndShade() {
        // A swatch is picked as the colour it is: the greys differ only in
        // their shade, so that is what has to come through.
        let greys = SpacePalette.greys.map { SpaceTheme(hex: $0) }
        XCTAssertEqual(greys[0].value, 100)
        XCTAssertEqual(greys[greys.count - 1].value, 0)
        XCTAssertEqual(Set(greys.map(\.value)).count, greys.count, "nine greys, nine shades")
        XCTAssertTrue(greys.allSatisfy { $0.sat == 0 })
    }
}
