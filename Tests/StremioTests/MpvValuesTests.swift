import Libmpv
import XCTest

@testable import Stremio

final class MpvValuesTests: XCTestCase {
    private var strings: [UnsafeMutablePointer<CChar>?] = []

    override func tearDown() {
        for pointer in strings { free(pointer) }
        strings = []
        super.tearDown()
    }

    private func cString(_ text: String) -> UnsafeMutablePointer<CChar>? {
        let pointer = strdup(text)
        strings.append(pointer)
        return pointer
    }

    private func node(_ format: mpv_format, _ fill: (inout mpv_node) -> Void = { _ in }) -> mpv_node {
        var node = mpv_node()
        node.format = format
        fill(&node)
        return node
    }

    func testConvertsScalarNodes() {
        XCTAssertEqual(
            JSONValue(node(MPV_FORMAT_STRING) { $0.u.string = cString("mpv v0.40.0") }), .string("mpv v0.40.0"))
        XCTAssertEqual(JSONValue(node(MPV_FORMAT_FLAG) { $0.u.flag = 1 }), .bool(true))
        XCTAssertEqual(JSONValue(node(MPV_FORMAT_FLAG) { $0.u.flag = 0 }), .bool(false))
        XCTAssertEqual(JSONValue(node(MPV_FORMAT_INT64) { $0.u.int64 = 42 }), .number(42))
        XCTAssertEqual(JSONValue(node(MPV_FORMAT_DOUBLE) { $0.u.double_ = 12.5 }), .number(12.5))
        XCTAssertEqual(JSONValue(node(MPV_FORMAT_DOUBLE) { $0.u.double_ = .nan }), .null)
        XCTAssertEqual(JSONValue(node(MPV_FORMAT_NONE)), .null)
    }

    func testConvertsTrackListNodes() {
        var keys = [cString("id"), cString("type"), cString("selected")]
        var values = [
            node(MPV_FORMAT_INT64) { $0.u.int64 = 1 },
            node(MPV_FORMAT_STRING) { $0.u.string = cString("video") },
            node(MPV_FORMAT_FLAG) { $0.u.flag = 1 },
        ]
        keys.withUnsafeMutableBufferPointer { keys in
            values.withUnsafeMutableBufferPointer { values in
                var map = mpv_node_list(num: 3, values: values.baseAddress, keys: keys.baseAddress)
                withUnsafeMutablePointer(to: &map) { map in
                    var track = node(MPV_FORMAT_NODE_MAP) { $0.u.list = map }
                    withUnsafeMutablePointer(to: &track) { track in
                        var array = mpv_node_list(num: 1, values: track, keys: nil)
                        withUnsafeMutablePointer(to: &array) { array in
                            XCTAssertEqual(
                                JSONValue(node(MPV_FORMAT_NODE_ARRAY) { $0.u.list = array }),
                                .array([.object(["id": .number(1), "type": .string("video"), "selected": .bool(true)])])
                            )
                        }
                    }
                }
            }
        }
    }

    func testMapsJSONToMpvValues() {
        XCTAssertEqual(MpvValue(.string("yes")), .string("yes"))
        XCTAssertEqual(MpvValue(.bool(true)), .flag(true))
        XCTAssertEqual(MpvValue(.number(2)), .int64(2))
        XCTAssertEqual(MpvValue(.number(-5)), .int64(-5))
        XCTAssertEqual(MpvValue(.number(12.5)), .double(12.5))
        XCTAssertNil(MpvValue(.null))
        XCTAssertNil(MpvValue(.array([])))
        XCTAssertNil(MpvValue(.object([:])))
    }

    func testMapsShellVideoProperties() {
        for name in ["vo", "ao", "osc", "input-default-bindings", "input-vo-keyboard"] {
            XCTAssertNil(MpvProperty.value(for: name, .string("no")), name)
        }
        XCTAssertEqual(MpvProperty.value(for: "hwdec", .string("d3d11va")), .string("auto"))
        XCTAssertEqual(MpvProperty.value(for: "hwdec", .string("auto-copy")), .string("auto"))
        XCTAssertEqual(MpvProperty.value(for: "hwdec", .string("no")), .string("no"))
        XCTAssertEqual(MpvProperty.value(for: "time-pos", .number(90.5)), .double(90.5))
        XCTAssertEqual(MpvProperty.value(for: "aid", .number(2)), .int64(2))
    }

    func testMapsCommands() {
        XCTAssertEqual(
            MpvCommand.arguments([.string("loadfile"), .string("http://x/v"), .string("replace"), .number(-1)]),
            ["loadfile", "http://x/v", "replace", "-1"])
        XCTAssertEqual(MpvCommand.arguments([.string("stop")]), ["stop"])
        XCTAssertNil(MpvCommand.arguments([.string("run"), .string("/bin/sh")]))
        XCTAssertNil(MpvCommand.arguments([.string("loadfile"), .null]))
        XCTAssertNil(MpvCommand.arguments([]))
    }

    func testMapsEndFileReasons() {
        let reasons: [(mpv_end_file_reason, String)] = [
            (MPV_END_FILE_REASON_EOF, "eof"), (MPV_END_FILE_REASON_STOP, "stop"), (MPV_END_FILE_REASON_QUIT, "quit"),
            (MPV_END_FILE_REASON_ERROR, "error"), (MPV_END_FILE_REASON_REDIRECT, "redirect"),
            (mpv_end_file_reason(rawValue: 99), "unknown"),
        ]
        for (reason, name) in reasons {
            XCTAssertEqual(MpvEndFile.reason(reason), name)
        }
        XCTAssertEqual(MpvEndFile.event(reason: MPV_END_FILE_REASON_EOF, error: 0), .ended(reason: "eof", error: nil))
        XCTAssertEqual(
            MpvEndFile.event(reason: MPV_END_FILE_REASON_ERROR, error: MPV_ERROR_LOADING_FAILED.rawValue),
            .ended(
                reason: "error",
                error: .object([
                    "code": .number(3), "message": .string("Stream failed to load: loading failed"),
                    "critical": .bool(true),
                ])))
    }

    func testRealMpvAcceptsShellVideoValues() throws {
        let handle = try XCTUnwrap(mpv_create())
        defer { mpv_terminate_destroy(handle) }
        mpv_set_option_string(handle, "vo", "null")
        mpv_set_option_string(handle, "ao", "null")
        XCTAssertEqual(mpv_initialize(handle), 0)

        let values: [(String, JSONValue, String)] = [
            ("volume", .number(50), "50.000000"),
            ("panscan", .number(1), "1.000000"),
            ("speed", .number(1.5), "1.500000"),
            ("sub-delay", .number(-0.25), "-0.250000"),
            ("sub-scale", .number(1), "1.000000"),
            ("sub-pos", .number(90), "90.000000"),
            ("aid", .number(2), "2"),
            ("sid", .string("no"), "no"),
            ("keepaspect", .bool(false), "no"),
            ("mute", .string("yes"), "yes"),
            ("sub-ass-override", .string("strip"), "strip"),
        ]
        for (name, json, expected) in values {
            let value = try XCTUnwrap(MpvProperty.value(for: name, json))
            XCTAssertEqual(value.set(name, on: handle), 0, name)
            let current = mpv_get_property_string(handle, name)
            defer { mpv_free(current) }
            XCTAssertEqual(current.map { String(cString: $0) }, expected, name)
        }
    }
}
