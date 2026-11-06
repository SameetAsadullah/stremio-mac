import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var mpv: MpvPlayerBackend?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let mpv = MpvPlayerBackend()
        if mpv == nil { Log.player.error("mpv failed to start") }
        let controller = WebViewController(
            player: mpv ?? LoggingPlayerBackend(), videoView: mpv.map(MpvVideoView.init))
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        mpv?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
