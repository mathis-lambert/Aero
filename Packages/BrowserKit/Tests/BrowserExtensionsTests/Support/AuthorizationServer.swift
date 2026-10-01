import Foundation
@preconcurrency import Network

/// A loopback-only provider example; every response belongs to this test, with no real account or external service.
final class AuthorizationServer: Sendable {
    let url: URL
    private let listener: NWListener

    init(response: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "aero.tests.authorization")
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        let bytes = Data(response.utf8)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + .seconds(5)) == .success, let port = listener.port,
              let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else {
            listener.cancel()
            throw CancellationError()
        }
        self.url = url
    }

    deinit { listener.cancel() }
}
