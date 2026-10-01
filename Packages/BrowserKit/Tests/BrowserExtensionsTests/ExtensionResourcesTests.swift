import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// Failure modes: a website reaches a private extension page, another extension origin,
// a nonmatching caller, or a path with ambiguous decoding; public wildcard resources stay usable.
@MainActor
@Test func websiteReturnsRespectExposedExtensionResources() async throws {
    let id = String(repeating: "a", count: 32)
    let manifest = #"{"manifest_version":3,"name":"Public return example","version":"1","web_accessible_resources":[{"resources":["return.html","public/*.html"],"matches":["https://example.test/*"]}]}"#
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-resource-example-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(manifest.utf8).write(to: folder.appending(path: "manifest.json"))
    let webExtension = try await WKWebExtension(resourceBaseURL: folder)
    let context = WKWebExtensionContext(for: webExtension)
    context.uniqueIdentifier = id
    WKWebExtension.MatchPattern.registerCustomURLScheme("chrome-extension")
    context.baseURL = try #require(URL(string: "chrome-extension://\(id)/"))
    let origin = try #require(URL(string: "https://example.test/"))
    for path in ["return.html?code=example#state", "public/return.html"] {
        #expect(ExtensionResources.allows(try #require(URL(string: path, relativeTo: context.baseURL)?.absoluteURL), from: origin, context: context))
    }
    for path in ["private.html", "public%2freturn.html", "public/%252e%252e/return.html", "chrome-extension://bbbb/return.html"] {
        #expect(!ExtensionResources.allows(try #require(URL(string: path, relativeTo: context.baseURL)?.absoluteURL), from: origin, context: context))
    }
    #expect(!ExtensionResources.allows(context.baseURL.appending(path: "return.html"), from: try #require(URL(string: "https://attacker.test/")), context: context))
}
