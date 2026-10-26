import Foundation

// Where closing a tab leaves you.
//
// A page opened from a page is for now, and closing it is a step back: you
// land on the page that opened it, rather than on whatever the row happens to
// put beside it. Chrome and Firefox both read it that way — Chromium's ranking
// in `TabStripModel::DetermineNewSelectedTabIndex`, and Firefox's
// `browser.tabs.selectOwnerOnClose`, which is on by default and returns "to
// the tab that opened this tab (its owner)".
//
// The order is Chromium's, over the tabs still holding their page: a tab this
// one opened (the page you went on to from it), then another tab the same page
// opened (links off one page, read one after another, each handing you to the
// next until the last hands you back), then that page itself. Sleep is what
// keeps a tab out of it: landing on one wakes it, which is a page fetched that
// nobody asked for (see Browser.awake). With none of the three open, the
// neighbour is the caller's business, exactly as it was.
//
// ⌘W on a pin isn't this: a pin is a place kept rather than a page opened, and
// Browser.close has its own case for putting one down.
//
// The chain is handed on when a tab goes: the tabs it opened are given to the
// page that opened it, so closing a link and then the page it came from still
// walks back up, one close at a time, as Chromium's FixOpeners arranges.

extension Browser {
    /// Where to land after `tab` goes — it is still in `row`, at `index`, when
    /// this is asked. Nil when nothing it came from is still open, which
    /// leaves the neighbour to the caller.
    static func landing(after tab: Tab, at index: Int, in row: [Tab]) -> Tab? {
        let holding = row.indices.filter { row[$0].id != tab.id && !row[$0].asleep }
        // The nearest of those to `index`, the right-hand side first when two
        // are as near, as the neighbour rule beside this one reads the row.
        func nearest(_ choose: (Tab) -> Bool) -> Tab? {
            holding
                .filter { choose(row[$0]) }
                .min { one, other in
                    let gap = abs(one - index), otherGap = abs(other - index)
                    return gap == otherGap ? one > other : gap < otherGap
                }
                .map { row[$0] }
        }
        // The page it went on to.
        if let wentOn = nearest({ $0.opener == tab.id }) { return wentOn }
        guard let opener = tab.opener else { return nil }
        // Another page the same one opened.
        if let beside = nearest({ $0.opener == opener }) { return beside }
        // The page itself.
        return nearest { $0.id == opener }
    }
}
