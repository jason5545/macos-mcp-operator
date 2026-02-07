import Foundation
import OperatorCore

@main
struct MacOSMCPOperatorMain {
    static func main() async {
        do {
            try await OperatorRuntime.run()
        } catch {
            let payload = "{\"jsonrpc\":\"2.0\",\"id\":\"startup\",\"error\":{\"code\":-32603,\"message\":\"Startup failed: \(error.localizedDescription)\"}}"
            FileHandle.standardOutput.write(Data(payload.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(1)
        }
    }
}
