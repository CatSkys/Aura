import XCTest
@testable import Aura

/// The list spaces are read from (Spaces.read): the order you put them in,
/// the first one included. It used to be read back with the first space
/// first whatever the file said, so a space carried away from the left jumped
/// home as soon as the column redrew.
@MainActor
final class SpaceOrderTests: XCTestCase {
    private static var world: String?

    override class func setUp() {
        super.setUp()
        let name = "space-order-\(UUID().uuidString.lowercased().prefix(8))"
        world = name
        setenv("AURA_PROBE", name, 1)
    }

    override class func tearDown() {
        Disk.drain()
        if let world, Store.world == world {
            try? FileManager.default.removeItem(at: Store.folder)
            UserDefaults(suiteName: "com.officecommun.search.test.\(world)")?.removePersistentDomain(forName: "com.officecommun.search.test.\(world)")
        }
        unsetenv("AURA_PROBE")
        super.tearDown()
    }

    private func space(_ name: String) -> Space {
        Space(id: UUID(), name: name, colour: 0)
    }

    /// The first space is written last and read back last.
    func testTheFirstSpaceKeepsThePlaceItWasGiven() {
        let first = Space(id: Space.firstID, name: "Personal", colour: 0)
        let work = space("Work")
        Spaces.write([work, first])
        XCTAssertEqual(Spaces.read().map(\.id), [work.id, first.id])
    }

    /// A list from before this, without the first space in it, gets one at the
    /// top: the window has to open somewhere.
    func testAListWithoutTheFirstSpaceGetsOneAtTheTop() {
        let work = space("Work")
        Spaces.write([work])
        let read = Spaces.read()
        XCTAssertEqual(read.first?.id, Space.firstID)
        XCTAssertEqual(read.dropFirst().map(\.id), [work.id])
    }

    /// The first space is Personal's, whatever the file says about it.
    func testTheFirstSpaceIsAlwaysPersonals() {
        var first = Space(id: Space.firstID, name: "Personal", colour: 0)
        first.profile = UUID()
        Spaces.write([first] + [space("Work")])
        XCTAssertNil(Spaces.read().first?.profile)
    }
}
