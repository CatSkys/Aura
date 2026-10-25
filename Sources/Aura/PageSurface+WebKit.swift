import AppKit
import WebKit

// The one place where WebKit answers for a page.
//
// `PageView` already is most of what `PageSurface` asks for — it is a
// `WKWebView`, so the address, the progress, both zooms, the delegates and the
// snapshot are its own, and every command `PageSurface` asks for is one it
// already answers. So the conformance is WebKit's own, plus the two members
// that say what it is.
//
// This is also the only file that names a page's engine, and the day a page is
// something else, it is the file that changes.

extension PageView: PageSurface {
    var view: NSView { self }
    var webKit: WKWebView { self }

}
