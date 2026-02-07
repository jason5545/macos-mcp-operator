import XCTest
@testable import MCPCore

final class VersioningTests: XCTestCase {
    func testSupportedVersionsContainAllPlannedRevisions() {
        XCTAssertEqual(MCPVersioning.supported, ["2025-11-25", "2025-06-18", "2025-03-26"])
    }

    func testNegotiationReturnsRequestedWhenSupported() {
        XCTAssertEqual(MCPVersioning.negotiate(clientRequestedVersion: "2025-06-18"), "2025-06-18")
    }

    func testNegotiationFallsBackToLatestWhenUnsupported() {
        XCTAssertEqual(MCPVersioning.negotiate(clientRequestedVersion: "2099-01-01"), "2025-11-25")
    }
}
