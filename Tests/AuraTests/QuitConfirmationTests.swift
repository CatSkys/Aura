import AppKit
import XCTest
@testable import Aura

/// What the Quit command asks before it quits: a card of Aura's own, not a
/// dialog, and the answer is the key being held (see Quitting.swift). What is
/// tested here is everything short of the quit itself — the app going is the
/// one thing this suite must not do, so the holding is only ever driven up to
/// the second that would take it.
///
/// The holding is driven through `hold`, and not through the event queue: a
/// local event monitor is called from the app's own loop, and a test bundle
/// has none — a key posted there is taken by `nextEvent` and seen by nothing.
@MainActor
final class QuitConfirmationTests: XCTestCase {
    private var previous: Any?

    override class func setUp() {
        setenv("AURA_PROBE", "quit-confirmation-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        previous = Store.settings.object(forKey: Preferences.confirmQuitKey)
        Store.settings.set(true, forKey: Preferences.confirmQuitKey)
        // The card is one for the whole app, so a test that left it up with a
        // monitor running would count into this one.
        settle()
    }

    override func tearDown() async throws {
        settle()
        Store.settings.set(previous, forKey: Preferences.confirmQuitKey)
    }

    func testOffByDefaultAndPreferencePersists() {
        Store.settings.removeObject(forKey: Preferences.confirmQuitKey)
        let prefs = Preferences()
        XCTAssertFalse(prefs.confirmsQuit)
        prefs.confirmsQuit = true
        XCTAssertTrue(Preferences().confirmsQuit)
        prefs.confirmsQuit = false
        XCTAssertFalse(Preferences().confirmsQuit)
    }

    /// Asking puts the card up and puts up no dialog: the window the old
    /// confirmation worked in is the thing this replaces.
    func testAskingPutsUpACardAndNoDialog() {
        Quitting.shared.ask()
        XCTAssertTrue(Quitting.shared.showing)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertEqual(Quitting.shared.progress, 0)
    }

    /// Asked again — a held ⌘Q hands the menu its equivalent again and again —
    /// there is still one card, and it is still counting from nothing.
    func testAskingAgainDoesNotStartOverOrStack() {
        Quitting.shared.ask()
        Quitting.shared.ask()
        XCTAssertTrue(Quitting.shared.showing)
        XCTAssertEqual(Quitting.shared.progress, 0)
    }

    /// Let go and it waits a moment and fades, rather than going at once.
    func testTheCardGoesAwayOnItsOwn() {
        Quitting.shared.ask()
        XCTAssertTrue(Quitting.shared.showing)
        spin(0.5)
        XCTAssertTrue(Quitting.shared.showing, "the card is still there within its lingering")
        spin(2)
        XCTAssertFalse(Quitting.shared.showing)
        XCTAssertEqual(Quitting.shared.progress, 0)
    }

    /// ⌘Q down fills the line; letting go stops the filling and puts the line
    /// back, which is what makes a tap ask and a hold quit.
    func testHoldingCountsAndLettingGoStops() throws {
        Quitting.shared.ask()
        Quitting.shared.hold(try key(.keyDown))
        spin(0.5)
        XCTAssertGreaterThan(Quitting.shared.progress, 0.3)
        XCTAssertLessThan(Quitting.shared.progress, 1, "half a second of holding must not have quit")
        let held = Quitting.shared.progress
        Quitting.shared.hold(try key(.keyUp))
        spin(0.3)
        XCTAssertEqual(Quitting.shared.progress, held, accuracy: 0.001,
                       "let go, the line stays where the holding stopped, so a second press can carry on")
        XCTAssertTrue(Quitting.shared.showing)
    }

    /// Pressing again picks the holding up again, and a card still up does not
    /// ask a second time.
    func testPressingAgainCountsAgain() throws {
        Quitting.shared.ask()
        Quitting.shared.hold(try key(.keyDown))
        spin(0.3)
        Quitting.shared.hold(try key(.keyUp))
        spin(0.2)
        let carried = Quitting.shared.progress
        XCTAssertGreaterThan(carried, 0.2)
        Quitting.shared.ask()
        Quitting.shared.hold(try key(.keyDown))
        spin(0.2)
        XCTAssertGreaterThan(Quitting.shared.progress, carried + 0.1, "the second press carries on from it")
        XCTAssertLessThan(Quitting.shared.progress, 1)
    }

    // MARK: - a key, and the run loop it is read from

    private func key(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12
        ))
    }

    /// Nothing left holding, and the card down.
    private func settle() {
        let quit = Quitting.shared
        guard quit.showing, let release = try? key(.keyUp) else { return }
        quit.hold(release)
        let until = Date().addingTimeInterval(3)
        while quit.showing, Date() < until { spin(0.1) }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
