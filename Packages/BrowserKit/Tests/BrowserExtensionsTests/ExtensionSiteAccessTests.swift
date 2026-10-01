import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// Failure modes: <all_urls> reaches registered extension schemes, or a saved
// explicit grant overrides the wildcard denial. Own pages and websites stay usable.
@MainActor
@Test func websiteGrantsDoNotExposeOtherExtensions() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-site-access-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(#"{"manifest_version":3,"name":"Host permission example","version":"1","host_permissions":["<all_urls>"]}"#.utf8)
        .write(to: folder.appending(path: "manifest.json"))
    let webExtension = try await WKWebExtension(resourceBaseURL: folder)
    WKWebExtension.MatchPattern.registerCustomURLScheme("chrome-extension")
    let context = WKWebExtensionContext(for: webExtension)
    context.baseURL = try #require(URL(string: "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"))
    let other = try #require(URL(string: "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/private.html"))
    try ExtensionSiteAccess.restore(["<all_urls>", "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/*"], on: context)
    #expect(context.hasAccess(to: try #require(URL(string: "https://example.test/"))))
    #expect(context.hasAccess(to: context.baseURL.appending(path: "private.html")))
    #expect(!context.hasAccess(to: other))
    #expect(!ExtensionSiteAccess.permits(try WKWebExtension.MatchPattern(string: "chrome-extension://*/*")))
    #expect(!ExtensionSiteAccess.permits(try WKWebExtension.MatchPattern(string: "webkit-extension://*/*")))
}

// Failure mode: granting `<all_urls>` later, as a permission prompt does, exposes another extension's pages. WebKit
// keeps the explicit denial over a later grant, so nothing re-applies it.
@MainActor
@Test func aLaterWebsiteGrantKeepsOtherExtensionsDenied() async throws {
    let loaded = try await LoadedExtension(manifest: #"{"manifest_version":3,"name":"Later grant example","version":"1","optional_host_permissions":["<all_urls>"]}"#)
    defer { loaded.close() }
    let context = try #require(loaded.owner.contexts[loaded.record.id])
    let other = try #require(URL(string: "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/private.html"))
    #expect(!context.hasAccess(to: other))
    context.setPermissionStatus(.grantedExplicitly, for: try WKWebExtension.MatchPattern(string: "<all_urls>"))
    #expect(context.hasAccess(to: try #require(URL(string: "https://example.test/"))))
    #expect(!context.hasAccess(to: other))
}
