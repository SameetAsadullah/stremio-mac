import XCTest

@testable import Stremio

final class StreamingServerConfigTests: XCTestCase {
    private let paths = StreamingServerConfig.Paths(
        applicationSupport: URL(fileURLWithPath: "/Users/me/Library/Application Support"),
        logs: URL(fileURLWithPath: "/Users/me/Library/Logs"))

    func testDataStaysOutOfTheOfficialAppFolder() {
        XCTAssertEqual(
            paths.dataDirectory.path,
            "/Users/me/Library/Application Support/com.sameetasadullah.stremio-mac")
        XCTAssertFalse(paths.serverData.path.contains("stremio-server"))
        XCTAssertEqual(paths.logFile.path, "/Users/me/Library/Logs/com.sameetasadullah.stremio-mac/server.log")
    }

    func testEnvironment() {
        let environment = StreamingServerConfig.environment(paths: paths, port: 11471, temporaryDirectory: "/tmp/x/")
        XCTAssertEqual(environment["APP_PATH"], paths.serverData.path)
        XCTAssertEqual(environment["HOME"], paths.dataDirectory.path)
        XCTAssertEqual(environment["STREMIO_SERVER_PORT"], "11471")
        XCTAssertEqual(environment["NO_HTTPS_SERVER"], "1")
        XCTAssertEqual(environment["HLS_V2_DISABLED"], "1")
    }

    func testPollStopsWhenTheCheckPasses() async {
        var calls = 0
        let ready = await StreamingServerConfig.poll(timeout: 5, interval: 0.01) {
            calls += 1
            return calls == 3
        }
        XCTAssertTrue(ready)
        XCTAssertEqual(calls, 3)
    }

    func testPollGivesUpAfterTheTimeout() async {
        var calls = 0
        let ready = await StreamingServerConfig.poll(timeout: 0.05, interval: 0.01) {
            calls += 1
            return false
        }
        XCTAssertFalse(ready)
        XCTAssertGreaterThan(calls, 1)
    }

    func testArguments() {
        XCTAssertEqual(StreamingServerConfig.arguments(preload: "/p.js", script: "/s.js"), ["-r", "/p.js", "/s.js"])
    }

    func testPortDefaultsAndOverride() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertEqual(StreamingServerConfig.port(from: defaults), 11470)
        defaults.set(11471, forKey: "server-port")
        XCTAssertEqual(StreamingServerConfig.port(from: defaults), 11471)
        defaults.set(80, forKey: "server-port")
        XCTAssertEqual(StreamingServerConfig.port(from: defaults), 11470)
        XCTAssertEqual(StreamingServerConfig.baseURL(port: 11471).absoluteString, "http://127.0.0.1:11471/")
    }

    func testExistingServerIsRecognised() {
        let body = Data(#"{"options":[],"values":{"cacheSize":2147483648},"baseUrl":"http://127.0.0.1:11470"}"#.utf8)
        XCTAssertTrue(StreamingServerConfig.isStremioServer(statusCode: 200, body: body))
    }

    func testOtherAnswersAreNotAStremioServer() {
        let body = Data(#"{"values":{}}"#.utf8)
        XCTAssertFalse(StreamingServerConfig.isStremioServer(statusCode: 404, body: body))
        XCTAssertFalse(StreamingServerConfig.isStremioServer(statusCode: 200, body: Data("<html>".utf8)))
        XCTAssertFalse(StreamingServerConfig.isStremioServer(statusCode: 200, body: Data(#"{"a":1}"#.utf8)))
    }

    func testRestartsTwiceWithBackoff() {
        XCTAssertEqual(StreamingServerConfig.restartDelay(restart: 1), 1)
        XCTAssertEqual(StreamingServerConfig.restartDelay(restart: 2), 5)
        XCTAssertNil(StreamingServerConfig.restartDelay(restart: 3))
    }
}
