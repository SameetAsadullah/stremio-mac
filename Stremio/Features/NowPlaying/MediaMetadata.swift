import Foundation

/// The argument of the web's `media.metadata` method.
struct MediaMetadata: Equatable {
    var title: String
    var artist: String?
    var artworkURL: URL?

    /// Nil without a title, the one field the web always sends.
    init?(_ json: JSONValue?) {
        guard let object = json?.objectValue, let title = object["title"]?.stringValue, !title.isEmpty else {
            return nil
        }
        self.title = title
        artist = object["artist"]?.stringValue
        artworkURL = object["artUrl"]?.stringValue.flatMap(URL.init(string:)).flatMap {
            ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil
        }
    }
}

/// The values stremio-web's Player route accepts in its `media-key` signal.
enum MediaKey: String {
    case playPause = "play-pause"
    case play
    case pause
    case nextTrack = "next-track"

    var signal: String { ShellMessage.signal("media-key", .string(rawValue)) }
}
