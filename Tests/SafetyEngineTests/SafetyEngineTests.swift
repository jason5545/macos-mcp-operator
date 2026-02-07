import XCTest
@testable import CoreTypes
@testable import SafetyEngine

final class SafetyEngineTests: XCTestCase {
    func testRestrictedModeAllowsWithoutApprovalFlow() async {
        let engine = SafetyEngine(mode: .restricted, appWhitelist: ["com.apple.Notes"])
        let fingerprint = await engine.makeFingerprint(toolName: "mouse_click", arguments: ["x": "1"])

        let decision = await engine.evaluate(
            toolName: "mouse_click",
            riskClass: .low,
            targetBundleID: "com.apple.Safari",
            confirmationToken: nil,
            argumentsFingerprint: fingerprint
        )

        if case .allow = decision {
            // success
        } else {
            XCTFail("Expected allow in v1.1 approval-disabled mode")
        }
    }

    func testRestrictedHighRiskDoesNotRequireToken() async {
        let engine = SafetyEngine(mode: .restricted, appWhitelist: ["com.apple.Notes"])
        let fingerprint = await engine.makeFingerprint(toolName: "key_chord", arguments: ["keys": "cmd+q"])

        let decision = await engine.evaluate(
            toolName: "key_chord",
            riskClass: .high,
            targetBundleID: "com.apple.Notes",
            confirmationToken: nil,
            argumentsFingerprint: fingerprint
        )

        if case .allow = decision {
            // success
        } else {
            XCTFail("Expected allow without confirmation token")
        }
    }

    func testFullAutoSkipsWhitelistAndHighRiskToken() async {
        let engine = SafetyEngine(mode: .full_auto, appWhitelist: [])
        let fingerprint = await engine.makeFingerprint(toolName: "mouse_click", arguments: ["x": "1"])

        let decision = await engine.evaluate(
            toolName: "mouse_click",
            riskClass: .high,
            targetBundleID: "com.apple.Safari",
            confirmationToken: nil,
            argumentsFingerprint: fingerprint
        )

        if case .allow = decision {
            // success
        } else {
            XCTFail("Expected allow in full_auto mode")
        }
    }
}
