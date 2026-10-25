import SwiftUI

// The band at the top of the column: the lights' corner, the door that folds
// the column away, and back, forward and reload beside it.
//
// The column goes down to 176 points and 72 of those are the lights' corner
// (see Metrics.sideLights), so what is left is not always room for four
// doors. The row is worked out from the column's width before it is drawn:
// the doors it holds, the gaps closing up as it narrows, and a "…" at the end
// keeping whatever gave way a click away rather than nowhere. The fold goes
// first — ⌘S folds the column from anywhere — and then reload, which ⌘R does
// too; the arrows stay longest, being the two the hand reaches for most. The
// doors themselves never change size: a row that shrinks its buttons as it
// narrows is one you have to look at twice to find the one you want.

struct SideBand: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    /// The lights' corner, before the band: none in full screen.
    var lights: CGFloat

    var body: some View {
        let plan = SideBand.plan(column: prefs.sideWidth, lights: lights)
        HStack(spacing: 0) {
            Color.clear.frame(width: lights)
            HStack(spacing: plan.gap) {
                if plan.fold { fold }
                if !plan.doors.isEmpty {
                    Helm(browser: browser, doors: plan.doors, gap: plan.gap)
                }
                if plan.more { MoreDoor(browser: browser, plan: plan) }
            }
            Spacer(minLength: 0)
        }
    }

    /// The column folded away, its edge and ⌘S the other two ways.
    private var fold: some View {
        Door(
            icon: prefs.sidePosition == .right ? "sidebar.right" : "sidebar.left",
            on: browser.folded,
            help: browser.folded ? "Show Sidebar" : "Hide Sidebar"
        ) { browser.toggleFold() }
    }
}

extension SideBand {
    /// A door's width, as Door draws it.
    static let door: CGFloat = 26
    /// The air between the doors: roomy while there is room, and closed up
    /// when there isn't, which is what buys the arrows their place in a
    /// column at its narrowest.
    static let wide: CGFloat = 4
    static let tight: CGFloat = 2
    /// The column's own padding, on either side (see SideBar's).
    static let pad: CGFloat = 10

    /// What the band holds, in the order it draws it.
    struct Plan {
        var fold: Bool
        var doors: [HelmDoor]
        var more: Bool
        var gap: CGFloat

        /// What the row takes beside the lights.
        var width: CGFloat {
            let count = doors.count + (fold ? 1 : 0) + (more ? 1 : 0)
            guard count > 0 else { return 0 }
            return CGFloat(count) * SideBand.door + CGFloat(count - 1) * gap
        }
    }

    /// Everything the column has room for, the roomier gaps first, and the
    /// rest in the "…". At its narrowest the column keeps the arrows and the
    /// "…"; at 208 points across, a window not in full screen, it keeps all
    /// four doors.
    static func plan(column: CGFloat, lights: CGFloat) -> Plan {
        let available = max(0, column - 2 * pad - lights)
        let whole = Plan(fold: true, doors: HelmDoor.allCases, more: false, gap: wide)
        if whole.width <= available { return whole }

        var fold = true
        var doors = HelmDoor.allCases
        for _ in 0...(doors.count + 1) {
            let plan = Plan(fold: fold, doors: doors, more: true, gap: tight)
            if plan.width <= available { return plan }
            if fold {
                fold = false
            } else if !doors.isEmpty {
                doors.removeLast()
            }
        }
        // Not even the "…" on its own: the row is as narrow as it goes.
        return Plan(fold: false, doors: [], more: true, gap: tight)
    }
}

/// The "…": the doors that gave way, kept in a menu instead of nowhere. It
/// wears the door's square and the door's wash under the pointer, so the row
/// reads as one thing whichever doors it happens to hold.
private struct MoreDoor: View {
    @ObservedObject var browser: Browser
    let plan: SideBand.Plan

    @Environment(\.greys) private var greys
    @Environment(\.sideInk) private var side

    @State private var hovering = false

    var body: some View {
        Menu { actions } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? side.ink.opacity(0.7) : side.muted)
                .frame(width: SideBand.door, height: SideBand.door)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? greys.hover : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Localized("More"))
        .help("More".localized)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    /// Only what the row gave up: the fold when it went, and each door that
    /// went with it.
    @ViewBuilder
    private var actions: some View {
        let tab = browser.active
        if !plan.fold {
            Button(browser.folded ? "Show Sidebar" : "Hide Sidebar") { browser.toggleFold() }
            if plan.doors.count < HelmDoor.allCases.count { Divider() }
        }
        if !plan.doors.contains(.back) {
            Button("Back") { browser.back() }
                .disabled(tab?.canGoBack != true)
        }
        if !plan.doors.contains(.forward) {
            Button("Forward") { browser.forward() }
                .disabled(tab?.canGoForward != true)
        }
        if !plan.doors.contains(.reload) {
            let loading = tab?.loading == true
            Button(Localized(loading ? "Stop" : "Reload")) {
                if loading { tab?.stop() } else { browser.reload() }
            }
            .disabled(tab?.isBlank ?? true)
        }
    }
}
