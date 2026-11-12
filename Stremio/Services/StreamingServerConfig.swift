import Foundation

/// What the app passes to the node process, and the decisions around it. No I/O, so tests can
/// check it without starting anything.
enum StreamingServerConfig {
    static let defaultPort = 11470

    /// `-server-port` moves the server to another port, for tests next to the official app.
    static func port(from defaults: UserDefaults = .standard) -> Int {
        let port = defaults.integer(forKey: "server-port")
        return (1024...65535).contains(port) ? port : defaultPort
    }

    static func baseURL(port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)/")! }

    static let applicationSupportName = "com.sameetasadullah.stremio-mac"

    struct Paths: Equatable {
        let dataDirectory: URL
        let script: URL
        let logFile: URL

        /// Never `~/Library/Application Support/stremio-server`, which belongs to the official app.
        init(applicationSupport: URL, logs: URL) {
            dataDirectory = applicationSupport.appendingPathComponent(applicationSupportName, isDirectory: true)
            script = dataDirectory.appendingPathComponent("server.js")
            logFile = logs.appendingPathComponent(applicationSupportName, isDirectory: true)
                .appendingPathComponent("server.log")
        }

        /// Where the server keeps its settings and torrent cache.
        var serverData: URL { dataDirectory.appendingPathComponent("server", isDirectory: true) }

        static func standard() -> Paths {
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return Paths(applicationSupport: support, logs: library.appendingPathComponent("Logs"))
        }
    }

    /// `HOME` points at the data folder so that nothing in the server reads the real home folder.
    /// The other flags turn off what mpv does not need: CORS checks, the HTTPS endpoint on port
    /// 12470, casting and the ffmpeg transcoder.
    static func environment(paths: Paths, port: Int, temporaryDirectory: String) -> [String: String] {
        [
            "HOME": paths.dataDirectory.path,
            "APP_PATH": paths.serverData.path,
            "TMPDIR": temporaryDirectory,
            "PATH": "/usr/bin:/bin",
            "NO_CORS": "1",
            "CASTING_DISABLED": "1",
            "NO_HTTPS_SERVER": "1",
            "HLS_V2_DISABLED": "1",
            "UV_THREADPOOL_SIZE": "16",
            "STREMIO_SERVER_PORT": String(port),
        ]
    }

    static func arguments(preload: String, script: String) -> [String] {
        ["-r", preload, script]
    }

    /// A Stremio server answers `/settings` with JSON that has a `values` object.
    static func isStremioServer(statusCode: Int, body: Data) -> Bool {
        guard statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return false }
        return json["values"] is [String: Any]
    }

    /// stremio-web checks the server only when the page loads, so the app waits this long for node
    /// before it loads the page anyway.
    static let readyTimeout: TimeInterval = 10
    static let readyPollInterval: TimeInterval = 0.2

    /// Calls `check` until it returns true or `timeout` passes. Returns the last result.
    static func poll(
        timeout: TimeInterval, interval: TimeInterval, check: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if await check() { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    /// Seconds to wait before restart number `restart` (1 is the first). `nil` means give up.
    static func restartDelay(restart: Int) -> TimeInterval? {
        switch restart {
        case 1: 1
        case 2: 5
        default: nil
        }
    }

    /// A run this long counts as healthy, so the restart count starts again.
    static let healthyRunSeconds: TimeInterval = 60
}
