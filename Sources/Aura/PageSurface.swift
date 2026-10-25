import AppKit
import Security
import WebKit

// What a page is, to everything in Aura that isn't WebKit.
//
// Arc taught the shape of this: a browser made of a native interface on one
// side and an engine on the other needs exactly one seam between them, and
// everything that isn't the engine talks to that seam. Aura already had half
// of one, by accident — `PageView` is a `WKWebView` with Aura's own opinions
// on top — but two dozen other files named `WKWebView` directly, so the engine
// was spread through the app rather than standing behind it.
//
// Two parts, and only one of them is meant to last:
//
//   - Everything above `直通 WebKit` is Aura's own idea of a page: an address,
//     a title, a progress figure, two kinds of zoom, a world to run a script
//     in, and a view that other views are allowed to carry around (Stage and
//     PaneStage put it in a stage; Float lifts it into a window above
//     everything and hands it back).
//   - Everything below it is a window cut into the engine, kept only so this
//     step changes no behaviour at all: configuration, delegates, snapshot
//     configuration, find results, capture state. The fix for each one is
//     already known — the events go that way next, then the shapes stop being
//     WebKit's — and deleting a line here makes the compiler name every caller
//     left, which is what the list is for.
//
// Not in here on purpose: `Bench`, `Swipe`, `ExtensionCapture`,
// `Substitutions`, `PopupGesture`, `FrameRate` and `Notifications` still take
// a `WKWebView`. Each is doing something that is WebKit's own business —
// driving a menu, asking a preference, watching a capture state, poking a
// selector — and a seam that covered those too would be a second copy of
// WebKit's header rather than a boundary.

@MainActor
protocol PageSurface: AnyObject {
    // MARK: - the page

    /// The view that is the page. Whoever shows it may move it between
    /// superviews; nothing else about it is theirs to keep.
    var view: NSView { get }
    /// The window it is in, which is also how "on screen" is asked.
    var window: NSWindow? { get }

    var title: String? { get }
    var url: URL? { get }
    var isLoading: Bool { get }
    var estimatedProgress: Double { get }

    var canGoBack: Bool { get }
    var canGoForward: Bool { get }

    /// What the card beside the address asks about the page's certificate.
    var hasOnlySecureContent: Bool { get }
    var serverTrust: SecTrust? { get }

    @discardableResult func load(_ request: URLRequest) -> WKNavigation?
    @discardableResult func loadFileURL(_ url: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation?
    @discardableResult func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation?
    @discardableResult func reload() -> WKNavigation?
    @discardableResult func reloadFromOrigin() -> WKNavigation?
    func stopLoading()
    @discardableResult func goBack() -> WKNavigation?
    @discardableResult func goForward() -> WKNavigation?

    /// The page laid out again at a size of its own (⌘+ and ⌘−), and the
    /// picture pushed around under a pinch — two different things that both
    /// look like zoom, and are reset together.
    var pageZoom: CGFloat { get set }
    var magnification: CGFloat { get set }
    func setMagnification(_ magnification: CGFloat, centeredAt point: CGPoint)

    /// A script, and where it runs. `evaluateInSearch` is Aura's own world
    /// (see `Web.world`), where its page scripts live and the site cannot see
    /// them; `evaluateJavaScript` is the page's.
    func evaluateJavaScript(_ javaScriptString: String,
                            completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)?)
    func evaluateInSearch(_ js: String, then: ((Any?) -> Void)?)

    /// An address, or a file on this Mac, with the folder a file page may
    /// read from worked out on the way (see `WKWebView.open`).
    func open(_ url: URL)

    var isInspectable: Bool { get set }

    // MARK: - what Aura's page does on its own

    /// The sideways swipe that can close a little window or a tab, the first
    /// frame held back until there is something to draw, the keys the tab
    /// switcher hands on, the page's own right-click menu closing. These are
    /// Aura's page's habits rather than WebKit's, so they live on this side of
    /// the seam even though the web view is what carries them out.
    var onPull: ((Pull?) -> Void)? { get set }
    var leave: (() -> Void)? { get set }
    var onTouch: (() -> Void)? { get set }
    var onKeys: (() -> Void)? { get set }
    var onMenuClosed: (() -> Void)? { get set }
    var onFirstFrame: (() -> Void)? { get set }
    var searchName: (() -> String?)? { get set }
    var onSearch: ((String) -> Void)? { get set }
    var unpainted: Bool { get }
    func holdForFirstFrame()
    func answer(free yes: Bool)

    // MARK: - 直通 WebKit（P2/P3 逐条删除；每删一条，编译器会指出还在用它的人）

    var webKit: WKWebView { get }

    var configuration: WKWebViewConfiguration { get }
    var navigationDelegate: (any WKNavigationDelegate)? { get set }
    var uiDelegate: (any WKUIDelegate)? { get set }
    var backForwardList: WKBackForwardList { get }

    /// WebKit's own picture of an open page, taken before a tab sleeps and
    /// given back when it wakes. Opaque on purpose.
    var interactionState: Any? { get set }

    var fullscreenState: WKWebView.FullscreenState { get }
    var allowsMagnification: Bool { get set }
    var allowsBackForwardNavigationGestures: Bool { get set }

    var cameraCaptureState: WKMediaCaptureState { get }
    var microphoneCaptureState: WKMediaCaptureState { get }
    func setCameraCaptureState(_ state: WKMediaCaptureState, completionHandler: (@MainActor @Sendable () -> Void)?)
    func setMicrophoneCaptureState(_ state: WKMediaCaptureState, completionHandler: (@MainActor @Sendable () -> Void)?)

    func takeSnapshot(with snapshotConfiguration: WKSnapshotConfiguration?,
                      completionHandler: (@escaping @MainActor @Sendable (NSImage?, (any Error)?) -> Void))
    func find(_ string: String, configuration: WKFindConfiguration,
              completionHandler: (@escaping @MainActor @Sendable (WKFindResult) -> Void))
    func startDownload(using request: URLRequest, completionHandler: (@escaping @MainActor @Sendable (WKDownload) -> Void))
}

extension PageSurface {
    /// Most of the calls in Aura want the answer and nothing else.
    func evaluateInSearch(_ js: String) { evaluateInSearch(js, then: nil) }
}
