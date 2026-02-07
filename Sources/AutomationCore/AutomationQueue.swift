import CoreTypes
import Foundation

public actor AutomationQueue {
    private struct QueueItem {
        let id: UUID
        let label: String
        let operation: @Sendable () async throws -> ActionReceipt
        let continuation: CheckedContinuation<ActionReceipt, Error>
    }

    private var queue: [QueueItem] = []
    private var runnerTask: Task<Void, Never>?
    private var currentTask: Task<ActionReceipt, Error>?
    private var currentActionID: UUID?

    public init() {}

    public func enqueue(label: String, operation: @escaping @Sendable () async throws -> ActionReceipt) async throws -> ActionReceipt {
        try await withCheckedThrowingContinuation { continuation in
            let item = QueueItem(id: UUID(), label: label, operation: operation, continuation: continuation)
            queue.append(item)
            ensureRunner()
        }
    }

    public func stopAll() async -> Int {
        var cancelled = queue.count
        for item in queue {
            let receipt = ActionReceipt(
                actionID: item.id.uuidString,
                status: .cancelled,
                message: "Cancelled by automation_stop"
            )
            item.continuation.resume(returning: receipt)
        }
        queue.removeAll()

        if let currentTask {
            cancelled += 1
            currentTask.cancel()
        }

        return cancelled
    }

    private func ensureRunner() {
        guard runnerTask == nil else { return }

        runnerTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while true {
            guard !queue.isEmpty else {
                runnerTask = nil
                return
            }

            let item = queue.removeFirst()
            currentActionID = item.id

            let task = Task<ActionReceipt, Error> {
                try await item.operation()
            }
            currentTask = task

            do {
                var receipt = try await task.value
                if receipt.actionID.isEmpty {
                    receipt.actionID = item.id.uuidString
                }
                item.continuation.resume(returning: receipt)
            } catch is CancellationError {
                let receipt = ActionReceipt(
                    actionID: item.id.uuidString,
                    status: .cancelled,
                    message: "Action \(item.label) was cancelled"
                )
                item.continuation.resume(returning: receipt)
            } catch {
                item.continuation.resume(throwing: error)
            }

            currentTask = nil
            currentActionID = nil
        }
    }
}
