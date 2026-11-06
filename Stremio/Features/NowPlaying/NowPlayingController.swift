import AppKit
import MediaPlayer

/// Now Playing and the media keys. The system sends media keys to the app that has Now Playing
/// info, so the commands are on only while a file is loaded and other players keep their keys
/// otherwise. Everything runs on the main thread.
final class NowPlayingController {
    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()
    private let sendKey: (MediaKey) -> Void
    private var metadata: MediaMetadata?
    private var playback = PlaybackSnapshot()
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: URL?

    init(sendKey: @escaping (MediaKey) -> Void, seek: @escaping (Double) -> Void) {
        self.sendKey = sendKey
        let keys: [(MPRemoteCommand, MediaKey)] = [
            (commands.playCommand, .play), (commands.pauseCommand, .pause),
            (commands.togglePlayPauseCommand, .playPause), (commands.nextTrackCommand, .nextTrack),
        ]
        for (command, key) in keys {
            command.addTarget { [weak self] _ in
                self?.sendKey(key)
                return .success
            }
        }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seek(event.positionTime)
            return .success
        }
        // The web has no previous-track media key.
        commands.previousTrackCommand.isEnabled = false
        setCommands(enabled: false)
    }

    func update(metadata: MediaMetadata) {
        self.metadata = metadata
        loadArtwork(metadata.artworkURL)
        publish()
    }

    func update(playback: PlaybackSnapshot) {
        self.playback = playback
        publish()
    }

    func stop() {
        update(playback: PlaybackSnapshot())
    }

    private func setCommands(enabled: Bool) {
        let all = [
            commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
            commands.nextTrackCommand, commands.changePlaybackPositionCommand,
        ]
        for command in all { command.isEnabled = enabled }
    }

    private func publish() {
        setCommands(enabled: playback.loaded)
        guard playback.loaded else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = NowPlayingInfo.dictionary(metadata: metadata, playback: playback, artwork: artwork)
        center.playbackState = playback.paused ? .paused : .playing
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        guard let url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkURL == url else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.publish()
            }
        }.resume()
    }
}
