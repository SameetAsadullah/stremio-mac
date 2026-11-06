import AppKit
import WebKit

/// Hosts stremio-web. The web view is transparent, over the player's video view and a black
/// background.
final class WebViewController: NSViewController {
    static let url = URL(string: "https://web.stremio.com/")!

    private(set) var bridge: ShellBridge?
    private let webView: WKWebView
    private let videoView: NSView?

    init(player: PlayerBackend, videoView: NSView?, streamingServerURL: URL) {
        self.videoView = videoView
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)

        let bridge = ShellBridge(
            webView: webView, player: player, allowedHost: Self.url.host ?? "",
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
        webView.load(URLRequest(url: Self.url))
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
        let leavesApp =
            navigationAction.navigationType == .linkActivated
            && navigationAction.request.url?.host != Self.url.host
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
        openExternally(navigationAction.request.url)
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
