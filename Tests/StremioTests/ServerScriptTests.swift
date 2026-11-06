import XCTest

@testable import Stremio

final class ServerScriptTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String) throws -> String {
        let url = directory.appendingPathComponent("server.js")
        try Data(text.utf8).write(to: url)
        return url.path
    }

    func testSHA256HexOfKnownInput() {
        XCTAssertEqual(
            ServerScript.sha256Hex(of: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testValidFileIsAccepted() throws {
        let path = try write("console.log('server');")
        let expected = ServerScript.sha256Hex(of: Data("console.log('server');".utf8))
        XCTAssertTrue(ServerScript.isValid(path, expectedSHA256: expected))
    }

    func testAlteredFileIsRejected() throws {
        let expected = ServerScript.sha256Hex(of: Data("console.log('server');".utf8))
        let path = try write("console.log('tampered');")
        XCTAssertFalse(ServerScript.isValid(path, expectedSHA256: expected))
    }

    func testMissingFileIsRejected() {
        XCTAssertFalse(ServerScript.isValid(directory.appendingPathComponent("none.js").path))
    }

    func testPinnedChecksumIsLowercaseSHA256() {
        XCTAssertEqual(ServerScript.sha256.count, 64)
        XCTAssertEqual(ServerScript.sha256, ServerScript.sha256.lowercased())
    }

    func testEnsureKeepsAValidFileWithoutDownloading() async throws {
        let path = try write("ok")
        let expected = ServerScript.sha256Hex(of: Data("ok".utf8))
        let result = await ServerScript.ensure(
            at: path, from: URL(string: "http://127.0.0.1:1/never")!, expectedSHA256: expected)
        XCTAssertEqual(result, path)
    }

    func testEnsureDeletesAFileWithTheWrongChecksum() async throws {
        let path = try write("tampered")
        let result = await ServerScript.ensure(
            at: path, from: URL(string: "http://127.0.0.1:1/never")!, expectedSHA256: "00")
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
