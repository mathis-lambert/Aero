import Foundation
import WebKit

/// JSON bridge available only to extension configurations. The calling view and origin identify the extension.
@MainActor
final class ExtensionBridge: NSObject, WKURLSchemeHandler {
    static let scheme = "aero-extension"
    private static let host = "aero"
    /// Allows downloads that transfer blob bytes as a data URL.
    private static let maximumBodyBytes = 64 * 1024 * 1024

    enum Failure: LocalizedError {
        case unknownRequest, invalidRequest, notAllowed(String)

        var errorDescription: String? {
            switch self {
            case .unknownRequest: "Aero does not provide this."
            case .invalidRequest: "The request is not valid."
            case .notAllowed(let permission): "The extension was not granted the \(permission) permission."
            }
        }
    }

    weak var owner: ProfileExtensions?
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let request = task.request
        guard let url = request.url, url.host() == Self.host, let caller = webView.url, let owner,
              let context = owner.controller.extensionContext(for: caller), owner.contexts[context.uniqueIdentifier] === context,
              let origin = request.value(forHTTPHeaderField: "Origin").flatMap(URL.init(string:)),
              origin.scheme == context.baseURL.scheme, origin.host() == context.baseURL.host(), origin.port == context.baseURL.port else {
            Self.respond(task, status: 403, body: ["error": Failure.invalidRequest.localizedDescription])
            return
        }
        let route = String(url.path.dropFirst())
        let data = request.httpBody ?? Data()
        guard data.count <= Self.maximumBodyBytes,
              let body = (data.isEmpty ? [:] : try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Self.respond(task, status: 400, body: ["error": Failure.invalidRequest.localizedDescription])
            return
        }
        let listening = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "listening" }?.value
        if route != "events/next", let listening {
            owner.listen(Set(listening.split(separator: ",").map(String.init)), for: context, from: webView, waits: false)
        }
        let key = ObjectIdentifier(task)
        running[key] = Task { [weak self, weak webView] in
            var status = 200
            var reply: [String: Any]
            do {
                guard let webView else { throw CancellationError() }
                let value = try await owner.handle(route, body, context: context, caller: webView)
                reply = ["value": value ?? NSNull()]
            } catch {
                status = 400
                reply = ["error": error.localizedDescription]
            }
            // A request the context abandoned, as when its page closed, gets no answer.
            guard self?.running.removeValue(forKey: key) != nil else { return }
            Self.respond(task, status: status, body: reply)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }

    /// A reply that is not JSON, which would be Aero's mistake, answers as an invalid request.
    private static func respond(_ task: any WKURLSchemeTask, status: Int, body: [String: Any]) {
        let fallback: [String: Any] = ["error": Failure.invalidRequest.localizedDescription]
        let valid = JSONSerialization.isValidJSONObject(body)
        guard let url = task.request.url, let data = try? JSONSerialization.data(withJSONObject: valid ? body : fallback),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": "application/json",
                  // The scheme is another origin than the extension's; only the context that asked reads the answer.
                  "Access-Control-Allow-Origin": task.request.value(forHTTPHeaderField: "Origin") ?? "null"
              ]) else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
