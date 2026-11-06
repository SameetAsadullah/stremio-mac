import AppKit
import WebKit

/// Connects stremio-web's shell transport to the window and the player.
final class ShellBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "shell"
    static let shellVersion = "0.1.0"

    /// Defines `chrome.webview` over the WebKit message handler, which is the transport
    /// stremio-web looks for. `__shellDeliver` is how the app sends messages back.
    static let userScript = """
        (() => {
          const listeners = new Set();
          window.chrome = window.chrome || {};
          window.chrome.webview = {
            postMessage: (message) => window.webkit.messageHandlers.\(handlerName).postMessage(message),
            addEventListener: (type, listener) => { if (type === 'message') listeners.add(listener); },
            removeEventListener: (type, listener) => { if (type === 'message') listeners.delete(listener); },
          };
          window.__shellDeliver = (data) => listeners.forEach((listener) => listener({ data }));
        })();
        """

    /// The mpv-based player has no use for the Qt shell's GPU path, the interface scale or
    /// the cache picker yet. `mpvConfig` is left out so the config picker stays hidden.
    static func properties(streamingServerURL: URL?) -> [(name: String, value: String)] {
        [
            ("shellVersion", shellVersion),
            ("streamingServerUrl", streamingServerURL?.absoluteString ?? ""),
            ("gpuVideoProcessing", "false"),
            ("nativeAssSubtitles", "true"),
            ("cacheDirectoryPicker", "false"),
            ("nativeInterfaceScale", "false"),
        ]
    }

    private weak var webView: WKWebView?
    private let player: PlayerBackend
    private let allowedOrigin: URL
    private let streamingServerURL: URL?
    private var observers: [NSObjectProtocol] = []

    init(webView: WKWebView, player: PlayerBackend, allowedOrigin: URL, streamingServerURL: URL?) {
        self.webView = webView
        self.player = player
        self.allowedOrigin = allowedOrigin
        self.streamingServerURL = streamingServerURL
        super.init()
        player.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.deliver(event.signal) }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func send(signal name: String, arg: JSONValue = .null) {
        deliver(ShellMessage.signal(name, arg))
    }

    private func deliver(_ json: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(json), let literal = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__shellDeliver(\(literal))") { _, error in
            if let error { Log.shell.error("deliver failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == allowedOrigin.host,
            message.frameInfo.securityOrigin.port == allowedOrigin.port,
            let text = message.body as? String
        else {
            Log.shell.error("dropped a message from an untrusted frame")
            return
        }
        do {
            switch try ShellMessage.parse(text) {
            case .initialize:
                Log.shell.info("INIT received")
                deliver(ShellMessage.initReply(properties: Self.properties(streamingServerURL: streamingServerURL)))
                Log.shell.info("INIT answered")
            case .invoke(let method):
                handle(method)
            }
        } catch {
            Log.shell.error("bad message: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ method: ShellMethod) {
        switch method {
        case .appReady:
            Log.shell.info("app-ready")
        case .quit:
            NSApp.terminate(nil)
        case .setVisibility(let fullscreen):
            if let fullscreen, let window = webView?.window,
                fullscreen != window.styleMask.contains(.fullScreen)
            {
                window.toggleFullScreen(nil)
            }
        case .mpvCommand(let args):
            player.command(args)
        case .mpvSetProperty(let name, let value):
            player.setProperty(name, value)
        case .mpvObserveProperty(let name):
            player.observeProperty(name)
        case .mpvSetGPUVideoProcessing(let enabled):
            player.setGPUVideoProcessing(enabled)
        case .unsupported(let name, _):
            Log.shell.debug("unsupported method \(name, privacy: .public)")
        }
    }

    /// Sends `win-visibility-changed` and `win-state-changed` as the window changes.
    func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                self?.windowChanged(window, closing: note.name == NSWindow.willCloseNotification)
            }
        }
    }

    // Visibility values follow Qt's QWindow::Visibility, which stremio-web was written against.
    // State 9 is the one stremio-web reads as "hidden", used for "pause on minimize".
    private func windowChanged(_ window: NSWindow, closing: Bool) {
        let fullscreen = window.styleMask.contains(.fullScreen)
        let visibility = closing ? 0 : window.isMiniaturized ? 3 : fullscreen ? 5 : 2
        send(
            signal: "win-visibility-changed",
            arg: .object([
                "visible": .bool(!closing && !window.isMiniaturized),
                "visibility": .number(Double(visibility)),
                "isFullscreen": .bool(fullscreen),
            ]))
        send(signal: "win-state-changed", arg: .object(["state": .number(window.isMiniaturized ? 9 : 0)]))
    }
}
