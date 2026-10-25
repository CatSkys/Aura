import Foundation
import WebKit

// The scripts a filter list asks a page to run — `##+js(set-constant, …)` and
// its like.
//
// Refusing a request is half of blocking. The other half is a site's own check
// for whether one was refused: a script that looks for an advert vendor's
// global or builds a bait element, and then covers the article until the
// blocker is turned off. Those checks are scripts too, and a script can be
// shown what it wants to see — which is what the lists' scriptlet rules do,
// and what Aura could not answer at all before.
//
// Resources/Shield/scriptlets.json is the list's half (Tools/filters.py makes
// it) and scriptlets.js is the running half. They go into the page's own world
// at the start of the document, before the page's first script, because a
// check that has already run cannot be answered.
//
// The rules travel with the sites they are for rather than being sorted out
// here: a frame from another site runs this document's copy of the script too,
// and only the frame knows its own host.
@MainActor
enum Scriptlets {
    /// Whether anything is there to inject at all. A build without the files
    /// blocks requests and hides boxes, and says nothing about either.
    static var isReady: Bool { watch != nil }

    static let watch: WKUserScript? = {
        guard let folder = Bundle.main.url(forResource: "Shield", withExtension: nil),
              let rules = try? String(contentsOf: folder.appendingPathComponent("scriptlets.json"),
                                      encoding: .utf8),
              let runtime = try? String(contentsOf: folder.appendingPathComponent("scriptlets.js"),
                                        encoding: .utf8),
              !rules.hasPrefix("[]")
        else { return nil }
        // Handed over as one script: the rules the list wrote, then the code
        // that reads them. In the page's own world, and in every frame — the
        // check being answered is the page's own, and it is not always the top
        // frame that runs it.
        return WKUserScript(source: "window.__auraScriptlets=\(rules);\n\(runtime)",
                            injectionTime: .atDocumentStart,
                            forMainFrameOnly: false,
                            in: .page)
    }()
}
