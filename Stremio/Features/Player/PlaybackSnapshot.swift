import Foundation

/// What the app outside the web page needs to know about playback. mpv reports it when a
/// property below changes or a seek ends, never on a timer, so `elapsed` is the position at that time.
struct PlaybackSnapshot: Equatable {
    var loaded = false
    var paused = false
    var elapsed = 0.0
    var duration = 0.0
    var speed = 1.0
}
