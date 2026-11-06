import IOKit.pwr_mgt

/// Keeps the display awake while a video plays.
final class DisplayWakeLock {
    private var assertion = IOPMAssertionID(kIOPMNullAssertionID)
    var isHeld: Bool { assertion != IOPMAssertionID(kIOPMNullAssertionID) }

    static func shouldHold(_ snapshot: PlaybackSnapshot) -> Bool {
        snapshot.loaded && !snapshot.paused
    }

    func update(_ snapshot: PlaybackSnapshot) {
        set(held: Self.shouldHold(snapshot))
    }

    func set(held: Bool) {
        if held, !isHeld {
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Stremio is playing video" as CFString, &assertion)
            if status != kIOReturnSuccess { Log.player.error("display wake lock failed: \(status)") }
        } else if !held, isHeld {
            IOPMAssertionRelease(assertion)
            assertion = IOPMAssertionID(kIOPMNullAssertionID)
        }
    }

    deinit { set(held: false) }
}
