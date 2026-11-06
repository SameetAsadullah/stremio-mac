import Foundation

/// A message from stremio-web, sent with `chrome.webview.postMessage`.
enum ShellRequest: Equatable {
    case initialize
    case invoke(ShellMethod)
}

/// The methods stremio-web calls with `{id: 0, type: 6, args: [name, ...args]}`.
enum ShellMethod: Equatable {
    case appReady
    case quit
    case setVisibility(fullscreen: Bool?)
    case mpvCommand([JSONValue])
    case mpvSetProperty(name: String, value: JSONValue)
    case mpvObserveProperty(String)
    case mpvSetGPUVideoProcessing(Bool)
    /// Methods the app does not implement, such as `media.status` and `discord-*`.
    case unsupported(name: String, args: [JSONValue])
}

enum ShellMessageError: Error, Equatable {
    case notJSON
    case unsupportedType(Int)
    case malformed(String)
}

enum ShellMessage {
    private enum MessageType: Int {
        case signal = 1
        case initialize = 3
        case invokeMethod = 6
    }

    private struct Envelope: Decodable {
        var type: Int
        var args: [JSONValue]?
    }

    static func parse(_ text: String) throws -> ShellRequest {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) else {
            throw ShellMessageError.notJSON
        }
        switch MessageType(rawValue: envelope.type) {
        case .initialize:
            return .initialize
        case .invokeMethod:
            guard let name = envelope.args?.first?.stringValue else {
                throw ShellMessageError.malformed("missing method name")
            }
            return .invoke(try method(name, Array(envelope.args?.dropFirst() ?? [])))
        default:
            throw ShellMessageError.unsupportedType(envelope.type)
        }
    }

    private static func method(_ name: String, _ args: [JSONValue]) throws -> ShellMethod {
        switch name {
        case "app-ready":
            return .appReady
        case "quit":
            return .quit
        case "win-set-visibility":
            return .setVisibility(fullscreen: args.first?.objectValue?["fullscreen"]?.boolValue)
        case "mpv-command":
            guard case .array(let command)? = args.first else { throw malformed(name) }
            return .mpvCommand(command)
        case "mpv-set-prop":
            guard case .array(let pair)? = args.first, pair.count == 2, let prop = pair[0].stringValue
            else { throw malformed(name) }
            return .mpvSetProperty(name: prop, value: pair[1])
        case "mpv-observe-prop":
            guard let prop = args.first?.stringValue else { throw malformed(name) }
            return .mpvObserveProperty(prop)
        case "mpv-set-gpu-video-processing":
            guard let enabled = args.first?.boolValue else { throw malformed(name) }
            return .mpvSetGPUVideoProcessing(enabled)
        default:
            return .unsupported(name: name, args: args)
        }
    }

    private static func malformed(_ method: String) -> ShellMessageError {
        .malformed("bad arguments for \(method)")
    }

    /// `[1, name, "", value]`: the tuple shape `useShell.ts` reads. Capabilities are the
    /// strings `"true"` and `"false"`; the `mpvConfig` capability is on only when its property exists.
    static func initReply(properties: [(name: String, value: String)]) -> String {
        let tuples = properties.map { JSONValue.array([.number(1), .string($0.name), .string(""), .string($0.value)]) }
        return encode(
            .object([
                "id": .number(0),
                "type": .number(Double(MessageType.initialize.rawValue)),
                "data": .object(["transport": .object(["properties": .array(tuples)])]),
            ]))
    }

    static func signal(_ name: String, _ arg: JSONValue = .null) -> String {
        encode(
            .object([
                "type": .number(Double(MessageType.signal.rawValue)),
                "args": .array([.string(name), arg]),
            ]))
    }

    private static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding a value built from these cases cannot fail.
        return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
    }
}
