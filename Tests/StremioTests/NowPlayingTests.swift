import MediaPlayer
import XCTest

@testable import Stremio

final class NowPlayingTests: XCTestCase {
    private func metadata(_ fields: [String: JSONValue]) -> MediaMetadata? {
        MediaMetadata(.object(fields))
    }

    func testMetadataFields() throws {
        let value = try XCTUnwrap(
            metadata(["title": .string("T"), "artist": .string("A"), "artUrl": .string("https://x/a.png")]))
        XCTAssertEqual(value.title, "T")
        XCTAssertEqual(value.artist, "A")
        XCTAssertEqual(value.artworkURL, URL(string: "https://x/a.png"))
    }

    func testMetadataOptionalFields() throws {
        let value = try XCTUnwrap(metadata(["title": .string("T"), "artUrl": .null]))
        XCTAssertNil(value.artist)
        XCTAssertNil(value.artworkURL)
    }

    func testMetadataNeedsTitleAndWebArtwork() throws {
        XCTAssertNil(metadata(["artist": .string("A")]))
        XCTAssertNil(metadata(["title": .string("")]))
        XCTAssertNil(MediaMetadata(nil))
        let local = try XCTUnwrap(metadata(["title": .string("T"), "artUrl": .string("file:///etc/passwd")]))
        XCTAssertNil(local.artworkURL)
    }

    func testInfoForPlayingVideo() throws {
        let value = try XCTUnwrap(metadata(["title": .string("T"), "artist": .string("A")]))
        let info = NowPlayingInfo.dictionary(
            metadata: value,
            playback: PlaybackSnapshot(loaded: true, paused: false, elapsed: 12, duration: 90, speed: 2),
            artwork: nil)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "T")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "A")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 2)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 12)
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 90)
        XCTAssertNil(info[MPMediaItemPropertyArtwork])
    }

    func testInfoForPausedVideoWithoutMetadata() {
        let info = NowPlayingInfo.dictionary(
            metadata: nil, playback: PlaybackSnapshot(loaded: true, paused: true, elapsed: 5, duration: 0, speed: 1),
            artwork: nil)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Stremio")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertNil(info[MPMediaItemPropertyArtist])
        XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])
    }

    func testMediaKeySignals() {
        XCTAssertEqual(MediaKey.playPause.signal, #"{"args":["media-key","play-pause"],"type":1}"#)
        XCTAssertEqual(MediaKey.play.signal, #"{"args":["media-key","play"],"type":1}"#)
        XCTAssertEqual(MediaKey.pause.signal, #"{"args":["media-key","pause"],"type":1}"#)
        XCTAssertEqual(MediaKey.nextTrack.signal, #"{"args":["media-key","next-track"],"type":1}"#)
    }
}
