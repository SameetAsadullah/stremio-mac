import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var mpv: MpvPlayerBackend?
    private let server = StreamingServer()
    private let mirror = WebMirror()
    private let wakeLock = DisplayWakeLock()
    private var statsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        if !mirror.start() { Log.web.error("the web app cannot be served") }
        // The test host is this app; tests must not start a node process.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { server.start() }
        let mpv = MpvPlayerBackend()
        if mpv == nil { Log.player.error("mpv failed to start") }
        let videoView = mpv.map(MpvVideoView.init)
        let controller = WebViewController(
            player: mpv ?? LoggingPlayerBackend(), videoView: videoView, streamingServerURL: server.baseURL,
            mirror: mirror)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.title = "Stremio"
        window.backgroundColor = .black
        window.center()
        window.setFrameAutosaveName("MainWindow")
        controller.bridge?.observe(window)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.mpv = mpv
        mpv?.onPlayback = { [weak self] snapshot in
            DispatchQueue.main.async { self?.wakeLock.update(snapshot) }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let mpv, let videoView, let target = UserDefaults.standard.string(forKey: "play") {
            play(target, mpv, videoView)
        }
    }

    /// `-play <path-or-url>` plays a file under the web view and logs draws every 10 s, to test
    /// playback and to measure power.
    private func play(_ target: String, _ mpv: MpvPlayerBackend, _ videoView: MpvVideoView) {
        mpv.command([.string("loadfile"), .string(target)])
        statsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            mpv.logStats(draws: videoView.videoLayer.takeDrawCount(), seconds: 10)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mpv?.shutdown()
        wakeLock.set(held: false)
        server.stop()
        mirror.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
