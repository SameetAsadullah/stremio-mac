import Foundation
import Network

/// Loopback HTTP server on 127.0.0.1 that serves Stremio's web app by mirroring web.stremio.com.
/// WebKit blocks an https page from calling the streaming server at http://127.0.0.1:11470
/// (mixed content). From a localhost origin that call is allowed, and localhost still counts as
/// a secure context.
final class WebMirror {
    static let mirrorOrigin = URL(string: "https://web.stremio.com")!
    /// A web origin includes its port. Keeping the port fixed keeps localStorage, so the login
    /// survives restarts. It is clear of the server's ports 11470 to 11474.
    static let preferredPort: UInt16 = 11480

    /// Web mirror: same path and query on web.stremio.com.
    /// An absolute or scheme-relative target would replace the mirror host.
    static func mirrorURL(forTarget target: String) -> URL? {
        guard target.hasPrefix("/"), !target.hasPrefix("//"),
            let url = URL(string: target, relativeTo: mirrorOrigin)?.absoluteURL,
            url.host == mirrorOrigin.host
        else { return nil }
        return url
    }

    /// The same page on the mirror, for a link to web.stremio.com. `nil` for any other link.
    static func localURL(for url: URL, port: UInt16) -> URL? {
        guard url.host == mirrorOrigin.host, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        parts.scheme = "http"
        parts.host = "127.0.0.1"
        parts.port = Int(port)
        return parts.url
    }

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.sameetasadullah.stremio-mac.mirror")

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    /// Starts listening and waits until it is ready. Returns false when it cannot listen.
    @discardableResult
    func start() -> Bool {
        guard listener == nil else { return true }
        if listen(on: Self.preferredPort) { return true }
        Log.web.error("port \(Self.preferredPort) is busy; using another port, so this run starts logged out")
        return listen(on: nil)
    }

    private func listen(on desired: UInt16?) -> Bool {
        let parameters = NWParameters.tcp
        let wanted = desired.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: wanted)
        guard let listener = try? NWListener(using: parameters) else {
            Log.web.error("mirror listener could not be created")
            return false
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .cancelled: ready.signal()
            case .failed(let error):
                Log.web.error("mirror listener failed: \(error.localizedDescription, privacy: .public)")
                ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 3)
        guard case .ready = listener.state, let bound = listener.port?.rawValue else {
            listener.cancel()
            return false
        }
        self.listener = listener
        port = bound
        Log.web.info("mirror listening on 127.0.0.1:\(Int(bound))")
        return true
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, buffer: Data())
    }

    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.serve(connection, head: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.readRequest(connection, buffer: buffer)
            }
        }
    }

    private func serve(_ connection: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, let url = Self.mirrorURL(forTarget: String(parts[1])) else {
            connection.cancel()
            return
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var request = URLRequest(url: url)
        request.httpMethod = parts[0] == "HEAD" ? "HEAD" : "GET"
        for key in ["accept", "accept-language", "range", "if-none-match", "if-modified-since", "user-agent"] {
            if let value = headers[key] { request.setValue(value, forHTTPHeaderField: key) }
        }
        Relay(connection: connection, request: request).start()
    }
}

/// Streams one mirror response back over one client connection.
private final class Relay: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private let request: URLRequest
    private let lock = NSLock()
    private var inflight = 0
    private var suspended = false

    init(connection: NWConnection, request: URLRequest) {
        self.connection = connection
        self.request = request
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 90
        URLSession(configuration: configuration, delegate: self, delegateQueue: nil).dataTask(with: request).resume()
    }

    private func fail() {
        let head = "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
        connection.send(
            content: Data(head.utf8), completion: .contentProcessed { [connection] _ in connection.cancel() })
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        var head = "HTTP/1.1 \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))\r\n"
        // URLSession already decompressed the body, so a Content-Length from an
        // encoded response would be wrong; let EOF (Connection: close) delimit it.
        let encoded = http.value(forHTTPHeaderField: "Content-Encoding") != nil
        let passthrough: Set<String> = [
            "content-type", "content-range", "accept-ranges", "last-modified", "etag", "cache-control",
        ]
        for (key, value) in http.allHeaderFields {
            let name = "\(key)".lowercased()
            if passthrough.contains(name) || (name == "content-length" && !encoded) { head += "\(key): \(value)\r\n" }
        }
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        inflight += data.count
        if inflight > 8_000_000 && !suspended {
            suspended = true
            dataTask.suspend()
        }
        lock.unlock()
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                    dataTask.cancel()
                    self.connection.cancel()
                    return
                }
                self.lock.lock()
                self.inflight -= data.count
                if self.suspended && self.inflight < 2_000_000 {
                    self.suspended = false
                    dataTask.resume()
                }
                self.lock.unlock()
            })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        if error != nil && task.response == nil {
            fail()
            return
        }
        connection.send(
            content: nil, contentContext: .finalMessage, isComplete: true,
            completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}
