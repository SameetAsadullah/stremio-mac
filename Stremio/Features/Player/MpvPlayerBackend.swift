import Foundation
import Libmpv

/// Plays video with libmpv. Client API calls run on one serial queue, so the main thread, which
/// renders, never waits for the mpv core (see "Threading" in libmpv's render.h).
final class MpvPlayerBackend: PlayerBackend {
    var onEvent: ((PlayerEvent) -> Void)?
    weak var videoLayer: MpvVideoLayer?
    let handle: OpaquePointer

    private let queue = DispatchQueue(label: "com.sameetasadullah.stremio-mac.mpv")
    // The properties below are used only on `queue`.
    private var terminated = false
    private var renderReady = false
    private var waiting: [() -> Void] = []
    private var observed: Set<String> = []
    private var loadId = 0
    private var readyLoadId: Int?

    private enum Reply: UInt64 {
        case web = 1
        case videoConfigured = 2
    }

    init?() {
        guard let handle = mpv_create() else { return nil }
        self.handle = handle
        let options = [
            ("vo", "libmpv"),
            // mpv's CoreAudio output crashed in its hotplug callback when the device list changed.
            ("ao", "avfoundation"),
            ("hwdec", "auto"),
            // ShellVideo learns that a file ended from END_FILE, which keep-open would hold back.
            ("keep-open", "no"),
            // Frames then arrive when they are due, so a render on the main thread never waits
            // for a frame's display time.
            ("video-timing-offset", "0"),
        ]
        for (name, value) in options {
            mpv_set_option_string(handle, name, value)
        }
        mpv_request_log_messages(handle, "warn")
        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            return nil
        }
        mpv_observe_property(handle, Reply.videoConfigured.rawValue, "vo-configured", MPV_FORMAT_FLAG)
        mpv_set_wakeup_callback(
            handle,
            { context in
                guard let context else { return }
                let backend = Unmanaged<MpvPlayerBackend>.fromOpaque(context).takeUnretainedValue()
                backend.queue.async { backend.drainEvents() }
            }, Unmanaged.passUnretained(self).toOpaque())
    }

    func command(_ args: [JSONValue]) {
        guard let strings = MpvCommand.arguments(args) else {
            Log.player.error("rejected command \(args.first?.stringValue ?? "?", privacy: .public)")
            return
        }
        whenRenderReady { [self] in
            if strings[0] == "loadfile" {
                loadId += 1
                readyLoadId = loadId
                emit(.videoReady(loadId: loadId, ready: false))
            }
            run(strings)
        }
    }

    func setProperty(_ name: String, _ value: JSONValue) {
        guard let mpvValue = MpvProperty.value(for: name, value) else {
            Log.player.info("ignored property \(name, privacy: .public)")
            return
        }
        whenRenderReady { [self] in
            let status = mpvValue.set(name, on: handle)
            if status < 0 { logError(status, "set \(name)") }
        }
    }

    func observeProperty(_ name: String) {
        Log.player.debug("observe \(name, privacy: .public)")
        queue.async { [self] in
            guard !terminated else { return }
            if observed.insert(name).inserted {
                mpv_observe_property(handle, Reply.web.rawValue, name, MPV_FORMAT_NODE)
            } else {
                // mpv sends the current value only on the first observe, and each new player page
                // waits for mpv-version again.
                emitCurrentValue(of: name)
            }
        }
    }

    func setGPUVideoProcessing(_ enabled: Bool) {
        // The Windows shell's Direct3D video processing has no Mac equivalent. ShellVideo's
        // hwdec property already selects hardware decoding.
        Log.player.info("ignored gpu video processing \(enabled)")
    }

    /// Called on the main thread by the video layer after it creates the render context.
    func renderContextCreated() {
        queue.async { [self] in
            renderReady = true
            for work in waiting { work() }
            waiting = []
        }
    }

    /// Called on the main thread by the video layer after it draws a frame of load `loadId`.
    func videoShown(loadId: Int) {
        queue.async { [self] in
            guard readyLoadId == loadId else { return }
            readyLoadId = nil
            emit(.videoReady(loadId: loadId, ready: true))
        }
    }

    /// libmpv requires the render context to be freed, on its GL thread, before the core is destroyed.
    func shutdown() {
        // Freeing the render context ends a playing file with an error the page must not get.
        queue.async { [self] in onEvent = nil }
        videoLayer?.freeRenderContext()
        queue.sync { [self] in
            guard !terminated else { return }
            terminated = true
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
        }
    }

    // Before mpv_render_context_create, a loadfile makes vo=libmpv fail and mpv disables video.
    // Properties wait too, so they keep their order relative to loadfile.
    private func whenRenderReady(_ work: @escaping () -> Void) {
        queue.async { [self] in
            guard !terminated else { return }
            if renderReady { work() } else { waiting.append(work) }
        }
    }

    private func emit(_ event: PlayerEvent) {
        onEvent?(event)
    }

    private func run(_ args: [String]) {
        let pointers = args.map { strdup($0) }
        defer { for pointer in pointers { free(pointer) } }
        var argv: [UnsafePointer<CChar>?] = pointers.map { UnsafePointer($0) } + [nil]
        let status = mpv_command(handle, &argv)
        if status < 0 { logError(status, args[0]) }
    }

    private func flag(_ name: String) -> Bool {
        var value: Int32 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 && value != 0
    }

    private func emitCurrentValue(of name: String) {
        var node = mpv_node()
        guard mpv_get_property(handle, name, MPV_FORMAT_NODE, &node) >= 0 else {
            emit(.propertyChanged(name: name, data: .null))
            return
        }
        defer { mpv_free_node_contents(&node) }
        emit(.propertyChanged(name: name, data: JSONValue(node)))
    }

    private func logError(_ status: Int32, _ action: String) {
        let message = String(cString: mpv_error_string(status))
        Log.player.error("\(action, privacy: .public) failed: \(message, privacy: .public)")
    }

    private func drainEvents() {
        while !terminated, let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
            process(event)
        }
    }

    private func process(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else { return }
            propertyChanged(property, reply: event.reply_userdata)
        case MPV_EVENT_END_FILE:
            guard let end = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else { return }
            emit(MpvEndFile.event(reason: end.reason, error: end.error))
        case MPV_EVENT_PLAYBACK_RESTART:
            playbackRestarted()
        case MPV_EVENT_LOG_MESSAGE:
            guard let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee else {
                return
            }
            let text = String(cString: message.text).trimmingCharacters(in: .newlines)
            Log.player.notice("mpv \(String(cString: message.prefix), privacy: .public): \(text, privacy: .public)")
        default:
            break
        }
    }

    private func propertyChanged(_ property: mpv_event_property, reply: UInt64) {
        if reply == Reply.videoConfigured.rawValue {
            let configured =
                property.format == MPV_FORMAT_FLAG
                && (property.data?.assumingMemoryBound(to: Int32.self).pointee ?? 0) != 0
            DispatchQueue.main.async { [weak self] in self?.videoLayer?.videoConfigured = configured }
            return
        }
        var data = JSONValue.null
        if property.format == MPV_FORMAT_NODE, let node = property.data?.assumingMemoryBound(to: mpv_node.self) {
            data = JSONValue(node.pointee)
        }
        emit(.propertyChanged(name: String(cString: property.name), data: data))
    }

    // ShellVideo shows the video, and hides its own loading background, once the load's
    // `ready: true` arrives. After the first playback restart the layer draws the current frame
    // and reports it with videoShown. A file without video is ready at once.
    private func playbackRestarted() {
        guard let id = readyLoadId else { return }
        if flag("vo-configured") {
            DispatchQueue.main.async { [weak self] in self?.videoLayer?.showVideo(loadId: id) }
        } else {
            readyLoadId = nil
            emit(.videoReady(loadId: id, ready: true))
        }
    }
}
