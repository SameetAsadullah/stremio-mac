import XCTest

@testable import Stremio

final class WebMirrorTests: XCTestCase {
    func testPathAndQueryMapToTheMirrorOrigin() {
        XCTAssertEqual(WebMirror.mirrorURL(forTarget: "/")?.absoluteString, "https://web.stremio.com/")
        XCTAssertEqual(
            WebMirror.mirrorURL(forTarget: "/scripts/main.js?v=1")?.absoluteString,
            "https://web.stremio.com/scripts/main.js?v=1")
    }

    func testTargetsThatChangeTheHostAreRejected() {
        XCTAssertNil(WebMirror.mirrorURL(forTarget: "https://evil.example/x"))
        XCTAssertNil(WebMirror.mirrorURL(forTarget: "//evil.example/x"))
        XCTAssertNil(WebMirror.mirrorURL(forTarget: "x"))
        XCTAssertNil(WebMirror.mirrorURL(forTarget: ""))
    }

    func testLinksToTheWebAppMapToTheMirror() {
        let url = URL(string: "https://web.stremio.com/#/discover?type=movie")!
        XCTAssertEqual(
            WebMirror.localURL(for: url, port: 11480)?.absoluteString, "http://127.0.0.1:11480/#/discover?type=movie")
        XCTAssertNil(WebMirror.localURL(for: URL(string: "https://example.com/")!, port: 11480))
    }
}
