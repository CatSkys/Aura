import CoreGraphics

// The mark. Written by ./Tools/mark.py from mark.svg — read in the app as a
// path at whatever size it is drawn, so it stays a crisp vector at every one.
// Edit the SVG and run the tool again; this file is not one to write by hand.

enum AuraMark {
    /// The SVG's own viewBox, in its own units.
    static let canvas = CGSize(width: 100, height: 100)

    /// Absolute M, L, C, Z: the path with its transform worked in and its
    /// arcs turned into cubics.
    static let data = "M23.58 23.26C28.11 14.29 37.12 8.47 47.16 8.03C57.2 7.59 66.69 12.6 71.98 21.14L88.8 48.3C94.17 56.97 94.47 67.86 89.58 76.81C84.68 85.77 75.35 91.4 65.15 91.55L36.31 92C26.2 92.15 16.74 87.01 11.37 78.44C6 69.87 5.5 59.12 10.05 50.09L23.58 23.26ZM51.99 22.81C56.21 22.06 65.28 29.84 69.18 34.84C73.07 39.84 74.63 46.77 75.36 52.83C76.09 58.89 76.23 67.24 73.58 71.22C70.94 75.2 64.17 78.57 59.49 76.71C54.81 74.86 48.12 66.34 45.51 60.1C42.9 53.87 42.78 45.52 43.85 39.31C44.93 33.09 47.77 23.55 51.99 22.81Z"
}
