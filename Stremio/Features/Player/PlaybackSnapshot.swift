import Foundation

/// What the app outside the web page needs to know about playback. mpv reports it only when
/// `pause` or `idle-active` change, never on a timer.
struct PlaybackSnapshot: Equatable {
    var loaded = false
    var paused = false
}
