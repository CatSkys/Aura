import SwiftUI

/// The card the space's dot opens: every space, the whole list every time,
/// and then what can be done to the one on screen.
///
/// It used to be an `NSMenu` (see Spaces.swift): a menu with more in it than
/// the room it is given is cut short by the system, its last rows folded away
/// under a chevron, and the spaces — the one thing this card is for — came
/// out as three and a half of them. Rows of our own are as many as the list
/// is: past eight, the list itself scrolls, and the rest of the card stays
/// where it is. The look is Arc's switcher: a symbol, a name, the key beside
/// it, one line of grey between the groups.
struct SpaceSwitcher: View {
    @ObservedObject var browser: Browser
    /// Puts the card away: it is a popover on the space's dot (see SpaceDot).
    let close: () -> Void

    @State private var page: Page = .spaces

    /// What the card is showing: the spaces, the space on screen's own
    /// settings, the icons a space can wear, or its colour — Arc's Space
    /// Style Editor, on a page of its own (see SpaceThemeEditor).
    private enum Page: Equatable { case spaces, settings, icons, colour }

    /// The card's width, and the colour page's: the editor's 27 swatches need
    /// the wider one.
    private var width: CGFloat { page == .colour ? 300 : 264 }
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
        .padding(7)
        .animation(Motion.quick, value: page)
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

            divider
            SpaceCardRow(title: "Show History…".localized, symbol: "clock.arrow.circlepath") {
                browser.recalling = true
                close()
            }
            SpaceCardRow(title: "Downloads…".localized, symbol: "arrow.down.circle") {
                browser.hoarding = true
                close()
            }

            divider
            SpaceCardRow(title: "Space Settings".localized, symbol: "slider.horizontal.3", next: true) {
                page = .settings
            }
        }
    }

    /// The key that goes to the space at `number`, as the menu showed it: the
    /// one Settings › Shortcuts has, and nothing at all once it is cleared.
    private func key(at number: Int) -> String {
        ShortcutStore.shared.key(for: "spaces.\(number)")?.display ?? ""
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
            SpaceCardRow(title: "Colour…".localized, symbol: "paintpalette", next: true) { page = .colour }
            SpaceCardRow(title: "Default Colour".localized, symbol: "arrow.uturn.backward") {
                browser.setSpaceTheme(here.id, to: nil)
            }
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
                    .buttonStyle(.plain)
                    .help(name.localized)
                    .accessibilityLabel(name.localized)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
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
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
    }

    /// Asked over the window once the card is out of the way: a sheet and a
    /// popover are two different things on screen at once, and the sheet goes
    /// under the popover if the popover is still there.
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

    static let height: CGFloat = 30

    var body: some View {
        Button(action: run) {
            HStack(spacing: 9) {
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
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Palette.muted)
                } else if next {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Palette.hover : (checked ? Palette.faint : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(checked ? "Selected".localized : "")
    }
}
