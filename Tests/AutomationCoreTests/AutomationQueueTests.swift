import XCTest
@testable import AutomationCore
@testable import CoreTypes

final class AutomationQueueTests: XCTestCase {
    func testStopAllCancelsPendingAndInFlightActions() async throws {
        let queue = AutomationQueue()

        async let first: ActionReceipt = queue.enqueue(label: "first") {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return ActionReceipt(actionID: "", status: .executed, message: "done")
        }

        async let second: ActionReceipt = queue.enqueue(label: "second") {
            return ActionReceipt(actionID: "", status: .executed, message: "done")
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let cancelled = await queue.stopAll()

        XCTAssertGreaterThanOrEqual(cancelled, 1)

        let firstReceipt = try await first
        let secondReceipt = try await second

        let statuses = [firstReceipt.status, secondReceipt.status]
        XCTAssertTrue(statuses.contains(.cancelled))
        XCTAssertTrue(statuses.allSatisfy { $0 == .cancelled || $0 == .executed })
    }
}
