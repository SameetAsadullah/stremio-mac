import XCTest

@testable import Stremio

final class ShellMessageTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testParsesInit() throws {
        XCTAssertEqual(try ShellMessage.parse(#"{"id":0,"type":3}"#), .initialize)
    }

    func testParsesSimpleMethods() throws {
        XCTAssertEqual(try ShellMessage.parse(#"{"id":0,"type":6,"args":["app-ready"]}"#), .invoke(.appReady))
        XCTAssertEqual(try ShellMessage.parse(#"{"id":0,"type":6,"args":["quit"]}"#), .invoke(.quit))
    }

    func testParsesVisibility() throws {
        let message = #"{"id":0,"type":6,"args":["win-set-visibility",{"fullscreen":true}]}"#
        XCTAssertEqual(try ShellMessage.parse(message), .invoke(.setVisibility(fullscreen: true)))
    }

    func testParsesMpvMethods() throws {
        XCTAssertEqual(
            try ShellMessage.parse(#"{"id":0,"type":6,"args":["mpv-command",["loadfile","http://x/v"]]}"#),
            .invoke(.mpvCommand([.string("loadfile"), .string("http://x/v")])))
        XCTAssertEqual(
            try ShellMessage.parse(#"{"id":0,"type":6,"args":["mpv-set-prop",["pause",false]]}"#),
            .invoke(.mpvSetProperty(name: "pause", value: .bool(false))))
        XCTAssertEqual(
            try ShellMessage.parse(#"{"id":0,"type":6,"args":["mpv-observe-prop","time-pos"]}"#),
            .invoke(.mpvObserveProperty("time-pos")))
        XCTAssertEqual(
            try ShellMessage.parse(#"{"id":0,"type":6,"args":["mpv-set-gpu-video-processing",true]}"#),
            .invoke(.mpvSetGPUVideoProcessing(true)))
    }

    func testKeepsUnknownMethods() throws {
        XCTAssertEqual(
            try ShellMessage.parse(#"{"id":0,"type":6,"args":["media.status",{"paused":true}]}"#),
            .invoke(.unsupported(name: "media.status", args: [try json(#"{"paused":true}"#)])))
    }

    func testRejectsBadMessages() {
        XCTAssertThrowsError(try ShellMessage.parse("nope")) {
            XCTAssertEqual($0 as? ShellMessageError, .notJSON)
        }
        XCTAssertThrowsError(try ShellMessage.parse(#"{"id":0,"type":9}"#)) {
            XCTAssertEqual($0 as? ShellMessageError, .unsupportedType(9))
        }
        XCTAssertThrowsError(try ShellMessage.parse(#"{"id":0,"type":6,"args":[]}"#))
        XCTAssertThrowsError(try ShellMessage.parse(#"{"id":0,"type":6,"args":["mpv-set-prop",["pause"]]}"#))
    }

    func testEncodesInitReply() {
        let reply = ShellMessage.initReply(properties: [("shellVersion", "0.1.0"), ("nativeAssSubtitles", "true")])
        XCTAssertEqual(
            reply,
            #"{"data":{"transport":{"properties":[[1,"shellVersion","","0.1.0"],"#
                + #"[1,"nativeAssSubtitles","","true"]]}},"id":0,"type":3}"#)
    }

    func testEncodesSignal() {
        XCTAssertEqual(
            ShellMessage.signal("win-state-changed", .object(["state": .number(9)])),
            #"{"args":["win-state-changed",{"state":9}],"type":1}"#)
        XCTAssertEqual(ShellMessage.signal("media-key"), #"{"args":["media-key",null],"type":1}"#)
    }

    func testEncodesPlayerEvents() {
        XCTAssertEqual(
            PlayerEvent.propertyChanged(name: "pause", data: .bool(true)).signal,
            #"{"args":["mpv-prop-change",{"data":true,"name":"pause"}],"type":1}"#)
        XCTAssertEqual(
            PlayerEvent.ended(reason: "eof", error: nil).signal,
            #"{"args":["mpv-event-ended",{"reason":"eof"}],"type":1}"#)
        XCTAssertEqual(
            PlayerEvent.videoReady(loadId: 2, ready: true).signal,
            #"{"args":["mpv-event-video-ready",{"loadId":2,"ready":true}],"type":1}"#)
    }
}
