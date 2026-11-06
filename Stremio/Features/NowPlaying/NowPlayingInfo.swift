import MediaPlayer

enum NowPlayingInfo {
    /// The elapsed time is set only here. The system moves it on from the rate, so it needs no
    /// updates while the video plays.
    static func dictionary(
        metadata: MediaMetadata?, playback: PlaybackSnapshot, artwork: MPMediaItemArtwork?
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata?.title ?? "Stremio",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: playback.paused ? 0.0 : playback.speed,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.elapsed,
        ]
        if let artist = metadata?.artist { info[MPMediaItemPropertyArtist] = artist }
        if playback.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = playback.duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        return info
    }
}
