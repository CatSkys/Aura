import AppKit
import WebKit

// Tabs you aren't using, put to sleep.
//
// A page open in a tab keeps its whole content process — a hundred to three
// hundred megabytes, running its timers, holding its sockets — for as long as
// the tab exists. Twenty tabs is two or three gigabytes spent on the nineteen
// nobody is looking at. So a tab left alone for half an hour is put aside, in
// one of two ways.
//
// The first few are kept: WebKit sets the page itself aside, JavaScript heap
// and all, and gives it back without a request being made — coming back to one
// of those is a frame's work, which is what a tab that was asleep should feel
// like (see Freeze.swift). Five of them, because a kept page is a page still
// costing its memory; past that, and when memory runs short, a tab gives its
// page back and keeps only what it takes to load it again where it was: its
// history, its scroll position, and a picture to show while it is rebuilt
// underneath (see Tab.sleep). That is the order Chrome keeps its tabs in —
// freeze, and discard only when the memory is needed.
//
// Some tabs never sleep, because waking them couldn't give back what they
// were doing: the one on screen, pinned tabs (those are put down by hand,
// with ⌘W), a tab playing sound, on a call, sending a download, holding its
// video out in the little window, or holding something typed and not sent.
// A pin stays awake only in the space on screen: in a space you aren't in it
// sleeps after the same wait as the tabs beside it, unless its site may send
// notifications, which a page asleep couldn't (#569). Five spaces of five
// pins was twenty-five pages that never let go.
//
// Half an hour is Normal. Settings › Tabs › How soon tabs sleep makes it
// two hours (Later) or ten minutes (Sooner).
//
// When macOS says memory is short, the wait shrinks, whatever was chosen: to
// five minutes on a warning, to nothing when it is critical — and the pages
// kept in memory are let go of first.

/// How soon tabs sleep, as chosen in Settings. Three levels rather than
/// numbers: what someone decides is how much a waking tab bothers them, not
/// how many minutes.
enum SleepPace: String, CaseIterable, Identifiable {
    case later, normal, sooner

    nonisolated static let key = "tabs.sleep.pace"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .later: return "Later"
        case .normal: return "Normal"
        case .sooner: return "Sooner"
        }
    }

    /// Away this long, a tab sleeps.
    var wait: TimeInterval {
        switch self {
        case .later: return 2 * 60 * 60
        case .normal: return 30 * 60
        case .sooner: return 10 * 60
        }
    }

    /// The wait, as the line under the choice reads it.
    var detail: String {
        switch self {
        case .later: return Localized("for two hours")
        case .normal: return Localized("for half an hour")
        case .sooner: return Localized("for ten minutes")
        }
    }

    /// The one chosen, Normal until someone chooses.
    nonisolated static var chosen: SleepPace {
        Store.settings.string(forKey: key).flatMap(SleepPace.init) ?? .normal
    }
}

extension Browser {
    /// How long a tab has to go without being looked at: the chosen pace's
    /// wait, or `sleep.after` in seconds — for the bench and the measurements.
    static var sleepAfter: TimeInterval {
        let set = Store.settings.double(forKey: "sleep.after")
        return set > 0 ? set : SleepPace.chosen.wait
    }

    /// Whether a tab that sleeps keeps its page in memory rather than giving it
    /// back — a frame to come back to instead of a load (see Freeze.swift).
    /// `sleep.freeze` in defaults turns it off: for a measurement that wants
    /// the old way, and for a Mac where the memory matters more than the wait.
    static var keepsPages: Bool {
        Store.settings.object(forKey: "sleep.freeze") as? Bool ?? true
    }

    /// Started once, at launch. The same look closes the tabs left alone
    /// longest, when tabs close themselves (see Closing.swift).
    func watchForSleep() {
        let every = min(60, max(5, Browser.sleepAfter / 4))
        let timer = Timer(timeInterval: every, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleepIdle()
                self?.closeLeftAlone()
            }
        }
        timer.tolerance = every / 4
        RunLoop.main.add(timer, forMode: .common)
        dozing = timer

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.pressure?.data else { return }
                // Memory first, and the pages kept in memory are the first of
                // it: they go without being looked at, and sleep the old way
                // from there.
                for tab in self.frozenTabs { tab.unfreeze() }
                self.sleepIdle(within: event.contains(.critical) ? 0 : 5 * 60)
            }
        }
        source.resume()
        pressure = source
    }

    /// The pages kept in memory while their tabs sleep, the one kept longest
    /// first: the first to be let go of when room is needed.
    var frozenTabs: [Tab] {
        (tabs + parkedTabs).filter(\.isFrozen).sorted { $0.frozenAt < $1.frozenAt }
    }

    /// Every tab that has gone long enough without being looked at, the one
    /// left longest first.
    func sleepIdle(within given: TimeInterval? = nil) {
        guard prefs.sleepsTabs else { return }
        let wait = given ?? Browser.sleepAfter
        let now = Date()
        // The rows of the other spaces too: parked is not the same as used.
        let idle = (tabs + parkedTabs)
            .filter { now.timeIntervalSince($0.touched) >= wait && awake(because: $0) == nil }
            .sorted { $0.touched < $1.touched }
        for tab in idle { self.sleep(tab) }
    }

    /// Why a tab has to stay awake — nil when nothing keeps it. The clock is
    /// the caller's business; this is everything else.
    func awake(because tab: Tab) -> String? {
        if visibleTabIDs.contains(tab.id) { return "on screen" }
        if tab.pin != nil, let kept = pinKept(tab) { return kept }
        if tab.bench { return "a bench tab" }
        if tab.isBlank { return "blank" }
        if tab.asleep { return "already asleep" }
        guard tab.built != nil else { return "no page" }
        if tab.loading { return "still loading" }
        return busy(tab)
    }

    func keepsAwake(_ tab: Tab) -> Bool {
        guard prefs.keepsSitesAwake, let host = tab.awakeHost else { return false }
        return (tab.shy ? tab.awakeSites : prefs.awakeSites).contains(host)
    }

    func keepAwake(_ on: Bool, for tab: Tab) {
        guard let host = tab.awakeHost else { return }
        if tab.shy {
            if on { tab.awakeSites.insert(host) } else { tab.awakeSites.remove(host) }
        } else {
            if on { prefs.awakeSites.insert(host) } else { prefs.awakeSites.remove(host) }
        }
    }

    /// Why a pin stays awake: always in the space on screen; in one you
    /// aren't in, only while its site may send notifications.
    private func pinKept(_ tab: Tab) -> String? {
        guard parked.values.contains(where: { $0.tabs.contains { $0 === tab } }) else { return "pinned" }
        return mayNotify(tab) ? "pinned, and its site may send notifications" : nil
    }

    /// Whether the site on the tab is allowed to send notifications (see
    /// Notifications.swift): answered yes, with notifications on in Settings.
    func mayNotify(_ tab: Tab) -> Bool {
        guard prefs.siteNotifications, !tab.shy, let url = tab.address,
              let scheme = url.scheme, let host = url.host(), !host.isEmpty else { return false }
        let site = Browser.origin(scheme, host, url.port ?? 0)
        return Store.settings.object(forKey: SiteNotifications.key(site)) as? Bool == true
    }

    /// What the page is in the middle of that letting it go would cut off:
    /// the part of staying awake that closing a tab asks too (Closing.swift).
    func busy(_ tab: Tab) -> String? {
        if keepsAwake(tab) { return "kept awake for this site" }
        if tab.noisy { return "playing sound" }
        if tab.floating || floating == tab.id { return "its video is out" }
        if let web = tab.built {
            if web.cameraCaptureState != .none || web.microphoneCaptureState != .none { return "on a call" }
            if #available(macOS 15.4, *), ExtensionCapture.screen(web.webKit) { return "recording the screen" }
            if downloading.contains(where: { $0.webView === web.webKit }) { return "downloading" }
        }
        if heldDialogs[tab.id]?.isEmpty == false || paneQuestions.contains(where: { $0.tab == tab.id }) {
            return "a question waiting"
        }
        // A sign-in window hands its answer back to the page that opened it.
        if let pair = activeSplit {
            if tabs.contains(where: { pair.contains($0.id) && $0.opener == tab.id }) {
                return "the page on screen came from it"
            }
        } else if active?.opener == tab.id {
            return "the page on screen came from it"
        }
        return nil
    }

    /// Asks the page whether it holds anything typed, pictures it, then lets
    /// it go — looking again at each step, since each takes a moment and you
    /// may have gone back to the tab in the meantime.
    ///
    /// Kept in memory rather than let go of, while there is room for it: waking
    /// a kept page is a frame's work, waking one that was let go of is a load
    /// (see Freeze.swift). The page kept longest makes room, and sleeps the
    /// old way from there.
    func sleep(_ tab: Tab, done: ((String) -> Void)? = nil) {
        if let reason = awake(because: tab) {
            done?(reason)
            return
        }
        tab.unsaved { [weak self, weak tab] typed in
            guard let self, let tab else { return }
            if typed {
                done?("holding something typed")
                return
            }
            if let reason = self.awake(because: tab) {
                done?(reason)
                return
            }
            tab.snapshot { [weak self, weak tab] picture in
                guard let self, let tab else { return }
                if let reason = self.awake(because: tab) {
                    done?(reason)
                    return
                }
                if Browser.keepsPages, tab.canFreeze {
                    while frozenTabs.count >= Freeze.budget, let oldest = frozenTabs.first {
                        oldest.unfreeze()
                    }
                    tab.freeze(picture: picture) { [weak tab] kept in
                        guard let tab else { return }
                        if !kept { tab.sleep(picture: picture) }
                        done?("asleep")
                    }
                    return
                }
                tab.sleep(picture: picture)
                done?("asleep")
            }
        }
    }
}
