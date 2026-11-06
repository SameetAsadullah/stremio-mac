import AppKit
import Libmpv

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let player = LoggingPlayerBackend()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = mpv_client_api_version()
        NSApp.mainMenu = MainMenu.make()
        let controller = WebViewController(player: player)
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
