import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// A real extension in WebKit's engine, installed and loaded as Aero does, checking from its service worker what Aero
// adds: globals an extension replaces or redefines, idle callbacks, declarations that survive WebKit's garbage collection,
// `management`, `idle`, one request for Aero's and WebKit's permissions together, offscreen documents that answer
// messages, `runtime.getContexts`, and a refusal for what it was not granted. Its button title reports.
// Needs access to macOS WebKit services.

private let timeout = Duration.seconds(20)

@MainActor
@Test func anExtensionRunsWithWhatAeroAdds() async throws {
    let fixture = try #require(Bundle.module.url(forResource: "Fixtures/runtime", withExtension: nil))
    let host = TestHost()
    let registry = ExtensionRegistry(folder: FileManager.default.temporaryDirectory.appendingPathComponent("aero-runtime-\(UUID().uuidString)"),
                                     nativeHostFolders: [], ephemeral: true) { _ in .nonPersistent() }
    registry.host = host
    let extensions = registry.extensions(for: UUID())
    let candidate = try await extensions.prepare(folder: fixture)
    #expect(candidate.permissions == ["idle", "management", "offscreen", "privacy", "storage"], "Aero's own permissions are asked for with WebKit's")
    host.grantsPermissions = true
    var record = InstalledExtension(id: candidate.identifier, version: "1.0", source: .folder(fixture),
                                    grantedPermissions: candidate.permissions, grantedSites: candidate.sites)
    record.packageID = candidate.packageID
    host.records = [record]
    try await extensions.load(record)

    let deadline = ContinuousClock.now + timeout
    var title = extensions.action(for: record.id)?.label
    while title == "running" || title == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(100))
        title = extensions.action(for: record.id)?.label
    }
    #expect(title == "ok")
    #expect(host.passwordExtension == nil, "Turning password saving back on gives the passwords back to Aero")
    #expect(host.permissionRequests.count == 1, "A combined request asks once")
    #expect(host.permissionRequests.first?.permissions == ["notifications", "tabs"])
    #expect(extensions.status(of: record.id)?.state == .running)
    try extensions.unload(record.id)
}
