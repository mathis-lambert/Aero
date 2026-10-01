import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// Identical extension origins in two profiles must resolve to their own grants and storage.
@MainActor
@Test func identicalExtensionOriginsKeepProfileServicesIsolated() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-profile-bridge-\(UUID())")
    let source = folder.appending(path: "source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(#"{"manifest_version":3,"name":"Profile bridge example","version":"1","permissions":["idle"],"action":{"default_title":"starting"},"background":{"service_worker":"worker.js"}}"#.utf8)
        .write(to: source.appending(path: "manifest.json"))
    try Data("browser.permissions.getAll().then(value => browser.action.setTitle({title:value.permissions.includes('idle') ? 'allowed' : 'denied'})).catch(error => browser.action.setTitle({title:'error: ' + error.message}));".utf8)
        .write(to: source.appending(path: "worker.js"))
    let registry = ExtensionRegistry(folder: folder.appending(path: "packages"), nativeHostFolders: [], ephemeral: true) { _ in .nonPersistent() }
    let first = registry.extensions(for: UUID()), second = registry.extensions(for: UUID())
    let one = try await first.prepare(folder: source), two = try await second.prepare(folder: source)
    var granted = InstalledExtension(id: one.identifier, version: "1", source: .folder(source), grantedPermissions: ["idle"], grantedSites: [])
    granted.packageID = one.packageID
    var refused = granted
    refused.packageID = two.packageID
    refused.grantedPermissions = []
    try await first.load(granted)
    try await second.load(refused)
    #expect(first.contexts[granted.id]?.baseURL == second.contexts[refused.id]?.baseURL)
    let deadline = ContinuousClock.now + .seconds(15)
    while (first.action(for: granted.id)?.label == "starting" || second.action(for: refused.id)?.label == "starting"), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(first.action(for: granted.id)?.label == "allowed")
    #expect(second.action(for: refused.id)?.label == "denied")
    #expect(second.status(of: refused.id)?.errors.isEmpty == true)
    try first.unload(granted.id)
    try second.unload(refused.id)
}
