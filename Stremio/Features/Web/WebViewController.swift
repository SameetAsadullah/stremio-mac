import AppKit
import WebKit

/// Hosts stremio-web, served by `WebMirror`. The web view is transparent, over the player's video view and a black
/// background.
final class WebViewController: NSViewController {
    private let mirror: WebMirror
    private(set) var bridge: ShellBridge?
    private let webView: WKWebView
    private let videoView: NSView?

    init(player: PlayerBackend, videoView: NSView?, streamingServerURL: URL, mirror: WebMirror) {
        self.mirror = mirror
        self.videoView = videoView
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)

        let bridge = ShellBridge(
            webView: webView, player: player, allowedOrigin: mirror.baseURL,
            streamingServerURL: streamingServerURL)
        self.bridge = bridge
        let controller = configuration.userContentController
        controller.add(WeakScriptHandler(bridge), name: ShellBridge.handlerName)
        controller.addUserScript(
            WKUserScript(source: ShellBridge.userScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
            webView.isInspectable = true
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        if let videoView {
            videoView.frame = container.bounds
            videoView.autoresizingMask = [.width, .height]
            container.addSubview(videoView)
        }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: mirror.baseURL))
    }

    private func openExternally(_ url: URL?) {
        guard let url, ["http", "https", "mailto", "stremio", "magnet"].contains(url.scheme?.lowercased() ?? "")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

extension WebViewController: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        let isLink = navigationAction.navigationType == .linkActivated
        if isLink || navigationAction.targetFrame == nil, let url,
            let local = WebMirror.localURL(for: url, port: mirror.port)
        {
            decisionHandler(.cancel)
            webView.load(URLRequest(url: local))
            return
        }
        let leavesApp = isLink && url?.host != mirror.baseURL.host
        if navigationAction.targetFrame == nil || leavesApp {
            openExternally(navigationAction.request.url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, let local = WebMirror.localURL(for: url, port: mirror.port) {
            webView.load(URLRequest(url: local))
        } else {
            openExternally(navigationAction.request.url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.web.error("navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        Log.web.error("load failed: \(error.localizedDescription, privacy: .public)")
    }
}
