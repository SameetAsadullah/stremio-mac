import XCTest

@testable import Stremio

final class DisplayWakeLockTests: XCTestCase {
    func testHoldsOnlyWhilePlaying() {
        XCTAssertTrue(DisplayWakeLock.shouldHold(PlaybackSnapshot(loaded: true, paused: false)))
        XCTAssertFalse(DisplayWakeLock.shouldHold(PlaybackSnapshot(loaded: true, paused: true)))
        XCTAssertFalse(DisplayWakeLock.shouldHold(PlaybackSnapshot(loaded: false, paused: false)))
        XCTAssertFalse(DisplayWakeLock.shouldHold(PlaybackSnapshot()))
    }

    func testAssertionFollowsSnapshots() {
        let lock = DisplayWakeLock()
        lock.update(PlaybackSnapshot(loaded: true, paused: false))
        XCTAssertTrue(lock.isHeld)
        lock.update(PlaybackSnapshot(loaded: true, paused: false))
        XCTAssertTrue(lock.isHeld)
        lock.update(PlaybackSnapshot(loaded: true, paused: true))
        XCTAssertFalse(lock.isHeld)
        lock.update(PlaybackSnapshot(loaded: true, paused: true))
        XCTAssertFalse(lock.isHeld)
    }
}
