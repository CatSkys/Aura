import SwiftUI

/// The card the space's dot opens: every space, the whole list every time,
/// and then what can be done to the one on screen.
///
/// It used to be an `NSMenu` (see Spaces.swift): a menu with more in it than
/// the room it is given is cut short by the system, its last rows folded away
/// under a chevron, and the spaces — the one thing this card is for — came
/// out as three and a half of them. Rows of our own are as many as the list
/// is: past eight, the list itself scrolls, and the rest of the card stays
/// where it is.
///
/// It is drawn as a card over the window rather than handed to a popover, so
/// it is made of the system's own liquid glass (`glassEffect`, which refracts
/// what lies under it and answers the pointer) and rounds its own corners: a
/// popover brings the system's corner, its own margin, and a tail on top.
struct SpaceSwitcher: View {
    @ObservedObject var browser: Browser
    /// Puts the card away (see SpaceCardOverlay).
    let close: () -> Void

    @State private var page: Page = .spaces

    /// What the card is showing: the spaces, the space on screen's own
    /// settings, the icons a space can wear, or its colour — Arc's Space
    /// Style Editor, on a page of its own (see SpaceThemeEditor).
    private enum Page: Equatable { case spaces, settings, icons, colour }

    /// The card's width — the column's own, as Arc's switcher is as wide as
    /// the sidebar it stands in — and the colour page's, whose 27 swatches
    /// need more room than the column has.
    private var width: CGFloat { page == .colour ? 300 : Metrics.side }

    /// How the card is cut: its corner, and the room it leaves around its rows.
    static let radius: CGFloat = 18
    private static let room: CGFloat = 9
    /// The line between the groups, in the ink the names are written in, so it
    /// reads as the card's own hairline rather than a grey of another kind.
    private static let rule = 0.12
    /// The spaces listed before the list scrolls, eight rows of them.
    private static let rowsShown = 8

    private var here: Space { browser.space }
    private var at: Int? { browser.spaces.firstIndex { $0.id == here.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case .spaces: spaces
            case .settings: settings
            case .icons: icons
            case .colour: colour
            }
        }
        .frame(width: width)
        .padding(Self.room)
    }

    // MARK: - the spaces

    /// Every space the window has, the one on screen ticked, each with the
    /// key that goes to it — the one Settings › Shortcuts gave it, if it was
    /// changed there.
    private var spaces: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { index, space in
                        SpaceCardRow(title: space.name, symbol: space.symbol,
                                     hint: key(at: index + 1),
                                     checked: space.id == browser.spaceID) {
                            if space.id != browser.spaceID { browser.switchSpace(to: space.id) }
                            close()
                        }
                    }
                }
            }
            .frame(height: CGFloat(min(browser.spaces.count, Self.rowsShown)) * SpaceCardRow.height)

            divider
            SpaceCardRow(title: "New Space".localized, symbol: "plus") {
                close()
                browser.askForSpace()
            }
            SpaceCardRow(title: "Space Settings".localized, symbol: "slider.horizontal.3", next: true) {
                page = .settings
            }

            divider
            SpaceCardRow(title: "Show History…".localized, symbol: "clock.arrow.circlepath",
                         hint: key("history.show")) {
                browser.recalling = true
                close()
            }
            SpaceCardRow(title: "Downloads…".localized, symbol: "arrow.down.circle",
                         hint: key("history.downloads")) {
                browser.hoarding = true
                close()
            }

            divider
            SpaceCardRow(title: "Settings…".localized, symbol: "gearshape", hint: key("app.settings")) {
                close()
                browser.tuning = true
            }
        }
    }

    /// The key that goes to the space at `number`, and the key a command has,
    /// as the menus show it: the one Settings › Shortcuts gave it, and nothing
    /// at all once it is cleared.
    private func key(at number: Int) -> String { key("spaces.\(number)") }

    private func key(_ command: String) -> String {
        ShortcutStore.shared.key(for: command)?.display ?? ""
    }

    // MARK: - this space's own

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpaceCardRow(title: here.name, symbol: "chevron.left", back: true) { page = .spaces }
            divider
            SpaceCardRow(title: Localized("Rename “\(here.name)”…"), symbol: "pencil") {
                rename()
            }
            SpaceCardRow(title: "Icon".localized, symbol: here.symbol, next: true) { page = .icons }
            // What tells one space from another at a glance, and what the
            // window's glass is tinted with while you are in it (see
            // SpaceTheme.swift): Arc's own palette, on a page of its own.
            // Back to the default is the palette's own Reset (see
            // SpaceThemeEditor): one door to it, on the page it belongs to.
            SpaceCardRow(title: "Colour…".localized, symbol: "paintpalette", next: true) { page = .colour }
            // The order is the swipe's, and ⌃1–⌃9's.
            if let at, at > 0 || at < browser.spaces.count - 1 { divider }
            if let at, at > 0 {
                SpaceCardRow(title: "Move Left".localized, symbol: "arrow.left") {
                    browser.moveSpace(here.id, to: at - 1)
                }
            }
            if let at, at < browser.spaces.count - 1 {
                SpaceCardRow(title: "Move Right".localized, symbol: "arrow.right") {
                    browser.moveSpace(here.id, to: at + 1)
                }
            }
            divider
            SpaceCardRow(title: folder.map { Localized("Downloads to “\($0)”…") } ?? "Downloads Folder…".localized,
                         symbol: "arrow.down.to.line") {
                downloads()
            }
            if folder != nil {
                SpaceCardRow(title: "Downloads to the Folder in Settings".localized, symbol: "arrow.uturn.backward") {
                    browser.setSpaceDownloads(here.id, to: nil)
                }
            }
            // The profile's first space stays: it is where everything was
            // before there were spaces.
            if !here.isFirst, here.id != browser.homeSpaceID {
                divider
                SpaceCardRow(title: Localized("Delete “\(here.name)”…"), symbol: "trash") { remove() }
            }
        }
    }

    /// The folder this space downloads into, by its name in the Finder.
    private var folder: String? {
        here.downloads.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    // MARK: - the icons a space can wear

    private var icons: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpaceCardRow(title: here.name, symbol: "chevron.left", back: true) { page = .settings }
            divider
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6), spacing: 4) {
                ForEach(Array(zip(Spaces.icons, Spaces.iconNames)), id: \.0) { symbol, name in
                    Button { browser.setSpaceIcon(here.id, to: symbol) } label: {
                        SpaceIcon(symbol: symbol, size: 13, shade: here.symbol == symbol ? Palette.ink : Palette.muted)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(here.symbol == symbol ? Palette.wash : .clear))
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(Press())
                    .help(name.localized)
                    .accessibilityLabel(name.localized)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 3)
        }
    }

    // MARK: - its colour

    /// Arc's Space Style Editor, under the row that opened it: a hue and how
    /// much of it, its 27 colours and the grain over the glass. The column
    /// beside the card is the preview.
    private var colour: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpaceCardRow(title: here.name, symbol: "chevron.left", back: true) { page = .settings }
            divider
            SpaceThemeEditor(browser: browser)
        }
    }

    // MARK: - the few things that ask

    private var divider: some View {
        Rectangle()
            .fill(Palette.ink.opacity(Self.rule))
            .frame(height: 1)
            .padding(.vertical, 6)
    }

    /// Asked over the window once the card is out of the way: a sheet and a
    /// card are two things on screen at once, and the sheet goes under the
    /// card if the card is still there.
    private func afterwards(_ ask: @escaping () -> Void) {
        close()
        DispatchQueue.main.async(execute: ask)
    }

    private func rename() {
        let name = here.name, id = here.id
        afterwards {
            Ask.name("Rename Space".localized, placeholder: name, initial: name, confirm: "Rename".localized) {
                browser.renameSpace(id, to: $0)
            }
        }
    }

    private func downloads() {
        let id = here.id
        afterwards { Ask.folder { browser.setSpaceDownloads(id, to: $0) } }
    }

    private func remove() {
        let name = here.name, id = here.id
        afterwards {
            Ask.sure(Localized("Delete “\(name)”?"),
                     detail: "Its tabs close, and its cookies and sign-ins are erased from this Mac. History and bookmarks stay.".localized,
                     confirm: "Delete".localized) {
                browser.deleteSpace(id)
            }
        }
    }
}

// MARK: - the card over the window

/// The card, up over the window's whole height: above the dot when it stands
/// at the column's foot, below it when it sits in the row of tabs, and with
/// the rest of the window under the pointer to put it away again.
struct SpaceCardOverlay: View {
    @ObservedObject var browser: Browser
    /// The card's own size, measured: the dot says where it stands, and the
    /// card has to know how tall it is to end above the dot rather than over
    /// it (its pages are not all the same height).
    @State private var size: CGSize = .zero

    var body: some View {
        if browser.spaceCardUp {
            GeometryReader { geo in
                let dot = anchor(in: geo.size)
                let above = dot.midY > geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    // Everything else puts it away: the page, the column, the
                    // bar. The card itself takes the clicks that are its own.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }

                    card
                        .offset(x: max(8, dot.minX - 6),
                                y: max(8, above ? dot.minY - size.height - 8 : dot.maxY + 8))
                        // The first pass has no size to place it by: drawn a
                        // moment later rather than a card's height wrong.
                        .opacity(size.height > 0 ? 1 : 0)
                }
                .onPreferenceChange(SpaceCardSize.self) { measured in
                    MainActor.assumeIsolated {
                        if size != measured { size = measured }
                    }
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(Motion.quick, value: browser.spaceCardUp)
        }
    }

    /// The card itself: the system's own liquid glass, which is what a card
    /// floating over everything should be made of — it refracts what lies
    /// under it and answers the pointer (macOS 26 and later). Before it, the
    /// window's glass over the page, as the column come loose is made (see
    /// CardGlass).
    @ViewBuilder
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: SpaceSwitcher.radius, style: .continuous)
        let content = SpaceSwitcher(browser: browser, close: close)
            .background(GeometryReader { box in
                Color.clear.preference(key: SpaceCardSize.self, value: box.size)
            })
            .fixedSize()
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: .black.opacity(0.22), radius: 26, y: 10)
        } else {
            content
                .background {
                    CardGlass(theme: browser.space.spaceTheme, radius: SpaceSwitcher.radius)
                        .clipShape(shape)
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
                .shadow(color: .black.opacity(0.20), radius: 24, y: 8)
        }
    }

    /// Where the dot stands, in the window's own coordinates. The dot reports
    /// it (see `SpaceDot`); until it has, the corner it would be in.
    private func anchor(in size: CGSize) -> CGRect {
        let frame = browser.spaceDotFrame
        guard frame.width > 0 else {
            return browser.prefs.sidebar
                ? CGRect(x: 10, y: size.height - 40, width: 26, height: 26)
                : CGRect(x: 90, y: 6, width: 26, height: 26)
        }
        return frame
    }

    private func close() { browser.spaceCardUp = false }
}

/// How big the card came out, for the overlay that places it (see
/// SpaceCardOverlay).
private struct SpaceCardSize: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Where the space's dot stands in the window: the card sits over it (see
/// SpaceCardOverlay).
struct SpaceDotFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// One line of the card: the space's own symbol, its name, the key beside it,
/// and a tick for the one on screen. The pointer's row takes a grey pill, as
/// the menus this replaces did.
private struct SpaceCardRow: View {
    let title: String
    let symbol: String
    var hint = ""
    var checked = false
    /// A row that opens another page of the card rather than doing something.
    var next = false
    /// A row that goes back, its symbol an arrow and its name what it returns to.
    var back = false
    let run: () -> Void

    @State private var hovering = false

    static let height: CGFloat = 32

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                SpaceIcon(symbol: symbol, size: 13, shade: back ? Palette.muted : Palette.ink)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: checked ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.muted)
                } else if next {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The tick says which space you are in; the row keeps no colour
            // of its own but the pointer's.
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Palette.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(checked ? "Selected".localized : "")
    }
}
