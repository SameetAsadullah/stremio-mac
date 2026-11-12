import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var mpv: MpvPlayerBackend?
    private let server = StreamingServer()
    private let mirror = WebMirror()
    private let wakeLock = DisplayWakeLock()
    private var nowPlaying: NowPlayingController?
    private var statsTimer: Timer?
    private var bridge: ShellBridge?
    /// Links that arrive before the window exists, as on a launch from a link.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        if !mirror.start() { Log.web.error("the web app cannot be served") }
        // The test host is this app; tests must not start a node process.
        let runsServer = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        if runsServer { server.start() }
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
        let server = server
        Task { @MainActor in
            if runsServer, await !server.waitUntilReady() {
                Log.server.error("the server did not answer in time; loading the web app anyway")
            }
            controller.loadWebApp()
        }
        self.mpv = mpv
        let bridge = controller.bridge
        self.bridge = bridge
        for url in pendingURLs { bridge?.open(url) }
        pendingURLs.removeAll()
        let nowPlaying = NowPlayingController(
            sendKey: { bridge?.send($0) },
            seek: { mpv?.seek(to: $0) })
        bridge?.onMediaMetadata = { nowPlaying.update(metadata: $0) }
        self.nowPlaying = nowPlaying
        mpv?.onPlayback = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.wakeLock.update(snapshot)
                self?.nowPlaying?.update(playback: snapshot)
            }
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

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let bridge else {
            pendingURLs += urls
            return
        }
        urls.forEach(bridge.open)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mpv?.shutdown()
        wakeLock.set(held: false)
        nowPlaying?.stop()
        server.stop()
        mirror.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
