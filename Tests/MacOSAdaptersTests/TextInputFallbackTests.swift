import XCTest
@testable import CoreTypes
@testable import MacOSAdapters

final class TextInputFallbackTests: XCTestCase {
    final class FallbackTestAdapter: SystemInputAdapter, @unchecked Sendable {
        var pasteAttempts = 0
        var keystrokeAttempts = 0

        override func pasteText(_ text: String) async throws {
            pasteAttempts += 1
            throw OperatorError("paste failed")
        }

        override func typeText(_ text: String) async throws {
            keystrokeAttempts += 1
        }
    }

    func testAutoModeFallsBackToKeystrokeWhenPasteFails() async throws {
        let adapter = FallbackTestAdapter()

        try await adapter.textInput("hello", mode: .auto)

        XCTAssertEqual(adapter.pasteAttempts, 1)
        XCTAssertEqual(adapter.keystrokeAttempts, 1)
    }
}
