import BrowserCore
import Foundation
@preconcurrency import Network
import Synchronization
import Testing

// An ephemeral session alone keeps the cookies a server sets for its lifetime and sends them back, which links the
// browser's own requests to each other. The anonymous session sends none.
@Test func anonymousSessionsSendNoCookieBack() async throws {
    let server = try RecordingServer(response: "HTTP/1.1 200 OK\r\nSet-Cookie: visitor=tracked\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
    let ephemeral = URLSession(configuration: .ephemeral)
    _ = try await ephemeral.data(from: server.url)
    _ = try await ephemeral.data(from: server.url)
    #expect(server.requests.last?.contains("visitor=tracked") == true, "Without the anonymous settings the cookie comes back")

    let anonymous = URLSession.anonymous(requestTimeout: 5, resourceTimeout: 5)
    _ = try await anonymous.data(from: server.url)
    _ = try await anonymous.data(from: server.url)
    #expect(server.requests.suffix(2).allSatisfy { !$0.lowercased().contains("cookie:") })
}

/// A loopback server answering every request with `response` and keeping what each request sent.
private final class RecordingServer: Sendable {
    let url: URL
    private let listener: NWListener
    private let log: Log

    var requests: [String] { log.all }

    init(response: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "aero.tests.recording")
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        let bytes = Data(response.utf8)
        let log = Log()
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                if let data { log.append(String(decoding: data, as: UTF8.self)) }
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
        self.log = log
    }

    deinit { listener.cancel() }
}

private final class Log: Sendable {
    private let entries = Mutex<[String]>([])
    func append(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
}
