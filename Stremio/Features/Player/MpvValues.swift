import Foundation
import Libmpv

extension JSONValue {
    /// Converts an mpv property value. Non-finite doubles become null because JSON cannot carry them.
    init(_ node: mpv_node) {
        switch node.format {
        case MPV_FORMAT_STRING, MPV_FORMAT_OSD_STRING:
            self = node.u.string.map { .string(String(cString: $0)) } ?? .null
        case MPV_FORMAT_FLAG:
            self = .bool(node.u.flag != 0)
        case MPV_FORMAT_INT64:
            self = .number(Double(node.u.int64))
        case MPV_FORMAT_DOUBLE:
            self = node.u.double_.isFinite ? .number(node.u.double_) : .null
        case MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list?.pointee, let values = list.values else {
                self = .array([])
                return
            }
            self = .array((0..<Int(list.num)).map { JSONValue(values[$0]) })
        case MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list?.pointee, let values = list.values, let keys = list.keys else {
                self = .object([:])
                return
            }
            var object: [String: JSONValue] = [:]
            for index in 0..<Int(list.num) {
                guard let key = keys[index] else { continue }
                object[String(cString: key)] = JSONValue(values[index])
            }
            self = .object(object)
        default:
            self = .null
        }
    }
}

/// A value for `mpv_set_property`.
enum MpvValue: Equatable {
    case string(String)
    case flag(Bool)
    case int64(Int64)
    case double(Double)

    /// JSON has one number type. Whole numbers go as int64 because mpv's integer properties
    /// (such as `aid`) reject doubles.
    init?(_ json: JSONValue) {
        switch json {
        case .string(let value):
            self = .string(value)
        case .bool(let value):
            self = .flag(value)
        case .number(let value) where value.isFinite:
            if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                self = .int64(Int64(value))
            } else {
                self = .double(value)
            }
        default:
            return nil
        }
    }

    var string: String {
        switch self {
        case .string(let value): return value
        case .flag(let value): return value ? "yes" : "no"
        case .int64(let value): return String(value)
        case .double(let value): return String(value)
        }
    }

    func set(_ name: String, on handle: OpaquePointer) -> Int32 {
        switch self {
        case .string(let value):
            return mpv_set_property_string(handle, name, value)
        case .flag(let value):
            var flag: Int32 = value ? 1 : 0
            return mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
        case .int64(let value):
            var number = value
            return mpv_set_property(handle, name, MPV_FORMAT_INT64, &number)
        case .double(let value):
            var number = value
            return mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &number)
        }
    }
}

enum MpvProperty {
    /// ShellVideo sends these for other shells. The app owns the window, the video and audio
    /// outputs and the input.
    static func isIgnored(_ name: String) -> Bool {
        ["vo", "ao", "wid", "osc", "gpu-api", "gpu-context"].contains(name) || name.hasPrefix("input-")
    }

    /// The value to set, or nil when the property is ignored or the value has no mpv form.
    static func value(for name: String, _ json: JSONValue) -> MpvValue? {
        if isIgnored(name) { return nil }
        if name == "hwdec" {
            // ShellVideo can ask for d3d11va or auto-copy. On a Mac only "auto" (VideoToolbox)
            // keeps the decoded frames on the GPU.
            return .string(json == .string("no") || json == .bool(false) ? "no" : "auto")
        }
        return MpvValue(json)
    }
}

enum MpvCommand {
    /// ShellVideo sends only these. Others, such as `run`, would let the page start processes.
    static let allowed: Set<String> = ["loadfile", "stop"]

    /// The string arguments for `mpv_command`, or nil when the command is not allowed.
    static func arguments(_ args: [JSONValue]) -> [String]? {
        guard let name = args.first?.stringValue, allowed.contains(name) else { return nil }
        let strings = args.compactMap { MpvValue($0)?.string }
        return strings.count == args.count ? strings : nil
    }
}

enum MpvEndFile {
    static func reason(_ reason: mpv_end_file_reason) -> String {
        switch reason {
        case MPV_END_FILE_REASON_EOF: return "eof"
        case MPV_END_FILE_REASON_STOP: return "stop"
        case MPV_END_FILE_REASON_QUIT: return "quit"
        case MPV_END_FILE_REASON_ERROR: return "error"
        case MPV_END_FILE_REASON_REDIRECT: return "redirect"
        default: return "unknown"
        }
    }

    /// The error has the shape of stremio-video's errors. Code 3 is its "Stream failed to load",
    /// and `critical` makes the player unload and show the error.
    static func event(reason: mpv_end_file_reason, error: Int32) -> PlayerEvent {
        let name = Self.reason(reason)
        guard reason == MPV_END_FILE_REASON_ERROR else { return .ended(reason: name, error: nil) }
        let message = String(cString: mpv_error_string(error))
        return .ended(
            reason: name,
            error: .object([
                "code": .number(3),
                "message": .string("Stream failed to load: \(message)"),
                "critical": .bool(true),
            ]))
    }
}
