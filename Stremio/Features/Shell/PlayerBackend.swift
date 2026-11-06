import Foundation

/// What stremio-video's `ShellVideo` asks of the player and listens to. Property names and values
/// are mpv's; values cross the bridge as JSON.
protocol PlayerBackend: AnyObject {
    /// Set by the bridge. The backend calls it from any thread.
    var onEvent: ((PlayerEvent) -> Void)? { get set }

    /// `["stop"]` and `["loadfile", url, ...]`.
    func command(_ args: [JSONValue])
    func setProperty(_ name: String, _ value: JSONValue)
    /// Emits `.propertyChanged` now and on every change. ShellVideo waits for `mpv-version`
    /// before it sends `loadfile`.
    func observeProperty(_ name: String)
    func setGPUVideoProcessing(_ enabled: Bool)
}

enum PlayerEvent: Equatable {
    case propertyChanged(name: String, data: JSONValue)
    /// `reason` is `eof`, `stop` or similar. A non-nil `error` is the object ShellVideo reports.
    case ended(reason: String?, error: JSONValue?)
    /// `ready` is false when a load starts and true when its first frame is ready.
    case videoReady(loadId: Int, ready: Bool)

    var signal: String {
        switch self {
        case .propertyChanged(let name, let data):
            return ShellMessage.signal("mpv-prop-change", .object(["name": .string(name), "data": data]))
        case .ended(let reason, let error):
            var arg: [String: JSONValue] = [:]
            if let reason { arg["reason"] = .string(reason) }
            if let error { arg["error"] = error }
            return ShellMessage.signal("mpv-event-ended", .object(arg))
        case .videoReady(let loadId, let ready):
            return ShellMessage.signal(
                "mpv-event-video-ready", .object(["loadId": .number(Double(loadId)), "ready": .bool(ready)]))
        }
    }
}

final class LoggingPlayerBackend: PlayerBackend {
    var onEvent: ((PlayerEvent) -> Void)?

    func command(_ args: [JSONValue]) { Log.player.debug("command with \(args.count) arguments") }
    func setProperty(_ name: String, _ value: JSONValue) {
        Log.player.debug("set \(name, privacy: .public)")
    }
    func observeProperty(_ name: String) { Log.player.debug("observe \(name, privacy: .public)") }
    func setGPUVideoProcessing(_ enabled: Bool) { Log.player.debug("gpu video processing \(enabled)") }
}
