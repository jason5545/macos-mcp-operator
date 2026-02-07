import XCTest
@testable import BrokerCore
@testable import CoreTypes

final class PermissionProbeTests: XCTestCase {
    func testMapsAutomationDeniedError1743() {
        let mapped = PermissionProbeMapper.mapFromAppleScriptFailure(
            "Not authorized to send Apple events to System Events. (-1743)"
        )

        XCTAssertEqual(mapped.status, .denied)
        XCTAssertEqual(mapped.errorCode, .automationNotAllowed)
    }

    func testMapsUserCanceledToNotDetermined() {
        let mapped = PermissionProbeMapper.mapFromAppleScriptFailure("User canceled. (-128)")
        XCTAssertEqual(mapped.status, .notDetermined)
        XCTAssertNil(mapped.errorCode)
    }

    func testMapsUnknownFailureToExecFailed() {
        let mapped = PermissionProbeMapper.mapFromAppleScriptFailure("Some random osascript failure")
        XCTAssertEqual(mapped.status, .error)
        XCTAssertEqual(mapped.errorCode, .execFailed)
    }
}
