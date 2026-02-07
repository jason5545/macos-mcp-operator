import BrokerCore
import ConfigStore
import Foundation

@main
struct MacOSMCPOperatorHostMain {
    static func main() async {
        do {
            let configStore = ConfigStore()
            let config = try await configStore.load()
            let server = BrokerServer(socketPath: config.broker.socketPath)
            let signalSources = installSignalHandlers(server: server)
            _ = signalSources
            try server.run()
        } catch {
            FileHandle.standardError.write(Data("Broker host failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func installSignalHandlers(server: BrokerServer) -> [DispatchSourceSignal] {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                server.stop()
            }
            source.resume()
            sources.append(source)
        }
        return sources
    }
}
