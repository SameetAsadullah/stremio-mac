import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var mpv: MpvPlayerBackend?
    private var statsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let mpv = MpvPlayerBackend()
        if mpv == nil { Log.player.error("mpv failed to start") }
        let videoView = mpv.map(MpvVideoView.init)
        let controller = WebViewController(player: mpv ?? LoggingPlayerBackend(), videoView: videoView)
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
