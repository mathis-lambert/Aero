import Foundation

/// The Chrome Web Store: its extension pages, and its update service, which serves packages and says
/// whether a newer one exists. See docs/EXTENSIONS.md › Installing.
enum WebStore {
    enum Failure: Error { case unavailable }

    private static let host = "chromewebstore.google.com"
    private static let service = URL(string: "https://clients2.google.com/service/update2/crx")!
    /// The Chromium version the service is asked for packages that run on.
    private static let chromiumVersion = "140.0"
    private static let session = URLSession.anonymous(requestTimeout: 60, resourceTimeout: 300)

    /// The extension a store page is about: `/detail/<name>/<identifier>` or `/detail/<identifier>`.
    static func extensionID(on url: URL) -> String? {
        guard url.host() == host else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "detail", let last = parts.last, isIdentifier(last) else { return nil }
        return last
    }

    static func isIdentifier(_ text: String) -> Bool { text.count == 32 && text.allSatisfy { ("a"..."p").contains($0) } }

    static func package(_ identifier: String) async throws -> Data {
        let (data, response) = try await session.data(from: query(identifier, version: nil, redirect: true))
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { throw Failure.unavailable }
        return data
    }

    /// The newer version the store has, if any.
    static func newerVersion(of identifier: String, than version: String) async throws -> String? {
        let (data, response) = try await session.data(from: query(identifier, version: version, redirect: false))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
        let reader = UpdateCheck()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw Failure.unavailable }
        return reader.status == "ok" ? reader.version.flatMap { $0 == version ? nil : $0 } : nil
    }

    private static func query(_ identifier: String, version: String?, redirect: Bool) -> URL {
        let request = "id=\(identifier)&v=\(version ?? "")&uc"
        return service.appending(queryItems: [
            URLQueryItem(name: "response", value: redirect ? "redirect" : "updatecheck"),
            URLQueryItem(name: "prodversion", value: chromiumVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: request)
        ])
    }

    /// Reads `<updatecheck status="…" version="…"/>` from the service's answer.
    private final class UpdateCheck: NSObject, XMLParserDelegate {
        var status: String?
        var version: String?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name == "updatecheck" else { return }
            status = attributes["status"]
            version = attributes["version"]
        }
    }
}
