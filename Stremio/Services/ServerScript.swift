import CryptoKit
import Foundation

/// Stremio's `server.js` is proprietary (© Smart Code OOD). The repository does not contain it.
/// The app downloads it once from Stremio's CDN and keeps the file only when its checksum matches.
enum ServerScript {
    static let version = "v4.21.1"
    /// SHA-256 of the official file. Change it together with `version`.
    static let sha256 = "405eb494d6708406a30e716c3cfb5abae7a5e9c7a8b79446d64c3f821385930f"
    static var downloadURL: URL { URL(string: "https://dl.strem.io/server/\(version)/desktop/server.js")! }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(_ path: String, expectedSHA256: String = sha256) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        return sha256Hex(of: data) == expectedSHA256
    }

    /// Returns the path of a verified `server.js` at `path`, downloading it first when needed.
    /// A file with the wrong checksum is deleted.
    static func ensure(
        at path: String, from url: URL = downloadURL, expectedSHA256: String = sha256
    ) async -> String? {
        if isValid(path, expectedSHA256: expectedSHA256) { return path }
        try? FileManager.default.removeItem(atPath: path)
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                Log.server.error("server.js download failed: HTTP status is not 200")
                return nil
            }
            guard isValid(temporary.path, expectedSHA256: expectedSHA256) else {
                Log.server.error("server.js download failed: checksum mismatch")
                return nil
            }
            try FileManager.default.moveItem(at: temporary, to: URL(fileURLWithPath: path))
            Log.server.info("server.js downloaded")
            return path
        } catch {
            Log.server.error("server.js download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
