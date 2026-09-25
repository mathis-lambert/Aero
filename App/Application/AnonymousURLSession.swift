import Foundation

extension URLSession {
    /// A session that sends no cookies or credentials and keeps no cache, for requests the browser
    /// makes on its own (icons, search suggestions), so they never reveal a profile's identity.
    static func anonymous(requestTimeout: TimeInterval, resourceTimeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }
}
