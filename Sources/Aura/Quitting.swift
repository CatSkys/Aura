import AppKit
import SwiftUI

// Quit, asked a second time — the way Arc asks it.
//
// Settings › General › Confirm before quitting used to put up a system alert:
// two buttons in a box, one of them the thing you were trying to do, so the
// hand went to it by reflex and nothing had really been asked. Arc answers
// the same worry with the key itself: ⌘Q brings a small card of Aura's own to
// the middle of the screen, and the app goes only once the key has been held
// down for a second — which no one does by accident, and which needs nothing
// to aim at.
//
// Let go early and the card stays a moment and fades. Press ⌘Q again while it
// is up and the holding carries on from where it stopped, so pressing twice,
// on purpose, gets there too.
//
// Nothing here takes the keys or the focus from the page: the card is a panel
// that cannot become key, and the press it counts is read from the event
// stream beside it.

@MainActor
final class Quitting: ObservableObject {
    static let shared = Quitting()

    /// How long the key is held before the app goes. Long enough that no one
    /// does it by accident, short enough that no one counts it.
    private let holdFor: TimeInterval = 1.0
    /// How long the card stays once the key is let go, so that a press reads
    /// as the app having answered rather than as a blink.
    private let lingering: TimeInterval = 1.6
    private let step: TimeInterval = 1.0 / 30

    /// Of the hold, 0 to 1: the line across the card.
    @Published private(set) var progress: Double = 0

    /// Whether the card is up, asked for or not, for the bench (see
    /// `./bench quitting`): a panel over every screen is read by its state
    /// rather than by its picture.
    var showing: Bool { panel != nil }

    private var panel: QuitPanel?
    private var keys: Any?
    private var resign: NSObjectProtocol?
    private var ticker: Timer?
    private var held: TimeInterval = 0
    /// Whether ⌘Q is down now, from the events below.
    private var down = false
    /// When it was last let go, for the lingering.
    private var releasedAt: Date?
    /// Gone once already: a terminate that AppKit is still working through
    /// must not be asked for twice.
    private var went = false

    // MARK: - asking

    /// Quit Aura in the menu, and ⌘Q with it: at once, unless Settings asks
    /// first.
    func ask() {
        guard Store.settings.bool(forKey: Preferences.confirmQuitKey) else {
            quit()
            return
        }
        // A held ⌘Q hands the menu its equivalent again and again; the card is
        // already up and the holding is already being counted.
        guard panel == nil else { return }
        went = false
        // Down when it came from the key, and not when it came from the menu
        // being clicked — then there is nothing yet to hold.
        down = NSApp.currentEvent?.type == .keyDown
        if !down { releasedAt = Date() }
        let made = QuitPanel(quitting: self)
        panel = made
        made.fit()
        // A test run keeps it off every screen, whatever it would show: its
        // progress is what is tested there.
        if !Store.testing {
            made.fade(in: !Motion.reduced)
        }
        watch()
        run()
    }

    // MARK: - counting the hold

    /// ⌘Q down and up, seen beside the menu rather than instead of it: what
    /// the menu does on the first press is ask, and what this does is count.
    /// Going to another app mid-hold is a letting go as well — that key's own
    /// release is delivered elsewhere, and a hold that never ended would quit
    /// on its own a second later.
    private func watch() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.hold(event) }
            return event
        }
        resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.down else { return }
                self.down = false
                self.releasedAt = Date()
            }
        }
    }

    /// One event from that monitor. Not private: a key pressed in a test run
    /// never reaches a monitor — the app is not running its own event loop
    /// there — so the holding is the tests' to drive, and this is where they
    /// join (see QuitConfirmationTests).
    func hold(_ event: NSEvent) {
        // Q's own letter for both, ⌘ only for the press: a hand that lets go
        // of ⌘ before Q sends Q's release with no ⌘ in it, and read as "still
        // down" the card would go on counting and quit by itself.
        guard event.charactersIgnoringModifiers?.lowercased() == "q" else { return }
        switch event.type {
        case .keyDown:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !down else { return }
            down = true
            releasedAt = nil
        case .keyUp:
            down = false
            releasedAt = Date()
        default:
            break
        }
    }

    private func run() {
        guard ticker == nil else { return }
        let made = Timer(timeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common modes, not the default one: the card is read while a menu or
        // a tracking loop of the app's own may be the one taking the run loop.
        RunLoop.main.add(made, forMode: .common)
        ticker = made
    }

    private func tick() {
        guard down else {
            guard let releasedAt, Date().timeIntervalSince(releasedAt) > lingering else { return }
            hide()
            return
        }
        held = min(holdFor, held + step)
        progress = held / holdFor
        guard held >= holdFor else { return }
        quit()
    }

    // MARK: - going

    private func quit() {
        guard !went else { return }
        went = true
        hide()
        NSApp.terminate(nil)
    }

    private func hide() {
        ticker?.invalidate()
        ticker = nil
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        down = false
        releasedAt = nil
        held = 0
        progress = 0
        guard let panel else { return }
        self.panel = nil
        // The card goes whether or not a test run would have shown it.
        panel.fade(out: !Motion.reduced)
    }
}

/// The card: borderless, never key or main, in the middle of the screen Aura
/// is on, over every space and full screen app.
private final class QuitPanel: NSPanel {
    private let content: NSHostingView<QuitCardView>

    init(quitting: Quitting) {
        content = NSHostingView(rootView: QuitCardView(quitting: quitting))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Its size for what it says, in the middle of the screen Aura is on.
    func fit() {
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        content.frame = NSRect(origin: .zero, size: size)
        let frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                           width: size.width, height: size.height)
        setFrame(frame, display: false)
    }

    func fade(in animated: Bool) {
        guard animated else {
            alphaValue = 1
            orderFrontRegardless()
            return
        }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    /// Faded rather than dropped, for the reason the recording pill is (see
    /// RecordingIndicator.swift): one frame up and the next gone reads as the
    /// screen glitching rather than as Aura answering.
    func fade(out animated: Bool) {
        guard animated else {
            orderOut(nil)
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        }
    }
}

/// What the card draws: the mark, what to do, and how much of the hold is
/// done.
struct QuitCardView: View {
    @ObservedObject var quitting: Quitting

    private static let line: CGFloat = 104

    var body: some View {
        VStack(spacing: 12) {
            Logomark()
                .fill(Palette.ink, style: FillStyle(eoFill: true))
                .aspectRatio(Logomark.canvas.width / Logomark.canvas.height, contentMode: .fit)
                .frame(height: 26)
            Text(Localized("Hold ⌘Q to quit"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Capsule()
                .fill(Palette.faint)
                .frame(width: QuitCardView.line, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: QuitCardView.line * quitting.progress, height: 3)
                }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Localized("Hold ⌘Q to quit"))
    }
}
