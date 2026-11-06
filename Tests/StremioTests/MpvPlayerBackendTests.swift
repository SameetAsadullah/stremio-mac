import XCTest

@testable import Stremio

final class MpvPlayerBackendTests: XCTestCase {
    func testObserveSendsMpvVersionEachTime() throws {
        let player = try XCTUnwrap(MpvPlayerBackend())
        defer { player.shutdown() }
        let received = expectation(description: "mpv-version twice")
        received.expectedFulfillmentCount = 2
        var versions: [String] = []
        player.onEvent = { event in
            if case .propertyChanged("mpv-version", .string(let version)) = event {
                versions.append(version)
                received.fulfill()
            }
        }
        player.observeProperty("mpv-version")
        player.observeProperty("mpv-version")
        wait(for: [received], timeout: 5)
        XCTAssertTrue(versions.allSatisfy { $0.hasPrefix("mpv ") }, "\(versions)")
    }

    func testLoadWaitsForRenderContext() throws {
        let player = try XCTUnwrap(MpvPlayerBackend())
        defer { player.shutdown() }
        let idle = expectation(description: "idle")
        idle.isInverted = true
        let ended = expectation(description: "load ends with an error")
        var events: [PlayerEvent] = []
        player.onEvent = { event in
            events.append(event)
            if case .ended = event { ended.fulfill() }
        }
        player.command([.string("loadfile"), .string("/nonexistent/video.mp4")])
        wait(for: [idle], timeout: 0.3)
        XCTAssertEqual(events, [], "events before the render context exists")
        player.renderContextCreated()
        wait(for: [ended], timeout: 5)
        XCTAssertEqual(events.first, .videoReady(loadId: 1, ready: false))
        guard case .ended(let reason, let error)? = events.last else { return XCTFail("\(events)") }
        XCTAssertEqual(reason, "error")
        XCTAssertEqual(error?.objectValue?["critical"], .bool(true))
    }
}
