import Foundation

/// Runs Stremio's streaming server (server.js) as a child node process, or reuses a server that
/// already answers on the port, such as the official app's.
final class StreamingServer {
    let port: Int
    var baseURL: URL { StreamingServerConfig.baseURL(port: port) }

    private let paths: StreamingServerConfig.Paths
    private let queue = DispatchQueue(label: "streaming-server")
    private var process: Process?
    private var stdin: Pipe?
    private var restarts = 0
    private var stopped = false

    init(port: Int = StreamingServerConfig.port(), paths: StreamingServerConfig.Paths = .standard()) {
        self.port = port
        self.paths = paths
    }

    /// Returns at once. The download and the start happen in the background.
    func start() {
        Task {
            if await isAlreadyRunning() {
                Log.server.info("a server already answers on port \(self.port); using it")
                return
            }
            try? FileManager.default.createDirectory(at: paths.serverData, withIntermediateDirectories: true)
            guard let script = await ServerScript.ensure(at: paths.script.path) else { return }
            queue.async { self.launch(script: script) }
        }
    }

    /// Ends the node process. Safe to call when it never started.
    func stop() {
        queue.sync {
            stopped = true
            guard let process, process.isRunning else { return }
            process.terminate()
            process.waitUntilExit()
        }
    }

    func isAlreadyRunning() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("settings"))
        request.timeoutInterval = 2
        guard let (body, response) = try? await URLSession.shared.data(for: request),
            let status = (response as? HTTPURLResponse)?.statusCode
        else { return false }
        return StreamingServerConfig.isStremioServer(statusCode: status, body: body)
    }

    private func launch(script: String) {
        guard !stopped else { return }
        guard let node = Bundle.main.url(forAuxiliaryExecutable: "node"),
            let preload = Bundle.main.path(forResource: "node-preload", ofType: "js")
        else {
            Log.server.error("node or node-preload.js is missing from the app bundle")
            return
        }
        guard let log = openLog() else { return }
        let process = Process()
        process.executableURL = node
        process.arguments = StreamingServerConfig.arguments(preload: preload, script: script)
        process.environment = StreamingServerConfig.environment(
            paths: paths, port: port, temporaryDirectory: NSTemporaryDirectory())
        process.currentDirectoryURL = paths.dataDirectory
        process.standardOutput = log
        process.standardError = log
        // The preload exits node when this pipe closes, which also happens if the app is killed.
        let stdin = Pipe()
        process.standardInput = stdin
        let startedAt = Date()
        process.terminationHandler = { [weak self] process in
            self?.queue.async { self?.exited(process, startedAt: startedAt, script: script) }
        }
        do {
            try process.run()
            self.process = process
            self.stdin = stdin
            Log.server.info("node started, pid \(process.processIdentifier), port \(self.port)")
        } catch {
            Log.server.error("node failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func exited(_ process: Process, startedAt: Date, script: String) {
        try? stdin?.fileHandleForWriting.close()
        guard !stopped else { return }
        Log.server.error("node exited with status \(process.terminationStatus) without being asked")
        if Date().timeIntervalSince(startedAt) >= StreamingServerConfig.healthyRunSeconds { restarts = 0 }
        restarts += 1
        guard let delay = StreamingServerConfig.restartDelay(restart: restarts) else {
            Log.server.error("node failed too often; not restarting")
            return
        }
        Log.server.info("restarting node in \(delay) s")
        queue.asyncAfter(deadline: .now() + delay) { self.launch(script: script) }
    }

    /// Keeps the log of the previous run in `server.prev.log`.
    private func openLog() -> FileHandle? {
        let manager = FileManager.default
        let directory = paths.logFile.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if restarts == 0 {
            let previous = directory.appendingPathComponent("server.prev.log")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: paths.logFile, to: previous)
            manager.createFile(atPath: paths.logFile.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: paths.logFile) else {
            Log.server.error("cannot open \(self.paths.logFile.path, privacy: .public)")
            return nil
        }
        _ = try? handle.seekToEnd()
        return handle
    }
}
