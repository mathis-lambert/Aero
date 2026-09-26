import Foundation
@preconcurrency import Network
import Synchronization

/// Serves the files in `Fixtures` over HTTP on the loopback interface while a test runs.
final class FixtureServer: Sendable {
    enum Failure: Error { case notReady }

    private static let readyTimeout = DispatchTimeInterval.seconds(5)
    private static let maximumRequestLength = 64 * 1024
    private static let contentTypes = ["html": "text/html; charset=utf-8", "png": "image/png", "csv": "text/csv", "json": "application/json"]
    /// Served as attachments, so the browser downloads them instead of displaying them.
    private static let attachmentExtensions: Set = ["csv"]

    let port: UInt16
    private let listener: NWListener
    private let log = RequestLog()
    private let queue = DispatchQueue(label: "app.getaero.browser.uitests.fixtures")

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [queue, log] connection in
            connection.start(queue: queue)
            Self.respond(on: connection, log: log)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + Self.readyTimeout) == .success, let port = listener.port?.rawValue else {
            listener.cancel()
            throw Failure.notReady
        }
        self.port = port
    }

    deinit { listener.cancel() }

    func stop() { listener.cancel() }

    /// The requests received so far for `fixture`, with their query.
    func requests(for fixture: String) -> [URLComponents] {
        log.paths.compactMap(URLComponents.init(string:)).filter { $0.path == "/" + fixture }
    }

    /// Where the app's search engines point in test runs (`AERO_TEST_SEARCH`).
    var searchEndpoint: URL { url("") }

    /// Uses `localhost` by default so app-side requests fall under App Transport Security's local
    /// networking exception; `127.0.0.1` serves the same files as another site.
    func url(_ fixture: String, host: String = "localhost") -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/" + fixture
        guard let url = components.url else { preconditionFailure("Invalid fixture name \(fixture)") }
        return url
    }

    private static func respond(on connection: NWConnection, log: RequestLog) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maximumRequestLength) { data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            log.record(path)
            let name = String(path.split(separator: "?").first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let response: Data
            if let file = fixtureURL(named: name), let body = try? Data(contentsOf: file) {
                let type = contentTypes[file.pathExtension] ?? "application/octet-stream"
                let disposition = attachmentExtensions.contains(file.pathExtension) ? file.lastPathComponent : nil
                response = header(status: "200 OK", type: type, length: body.count, attachment: disposition) + body
            } else {
                response = header(status: "404 Not Found", type: "text/plain", length: 0, attachment: nil)
            }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func fixtureURL(named name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        let bundle = Bundle(for: BundleToken.self)
        return bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: nil)
    }

    private static func header(status: String, type: String, length: Int, attachment: String?) -> Data {
        let disposition = attachment.map { "Content-Disposition: attachment; filename=\"\($0)\"\r\n" } ?? ""
        return Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\n\(disposition)Cache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
    }

    private final class BundleToken {}

    /// Paths with their query, in the order they arrived.
    private final class RequestLog: Sendable {
        private let storage = Mutex<[String]>([])
        var paths: [String] { storage.withLock { $0 } }
        func record(_ path: String) { storage.withLock { $0.append(path) } }
    }
}
