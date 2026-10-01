import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// Failure modes: deleting an unloaded persistent context, absent storage areas, retained local/sync data,
// and retrying a durable removal intent after the context has already been unloaded.
@MainActor
@Test(arguments: [false, true])
func removingPersistentExtensionDeletesItsStorage(unloadFirst: Bool) async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-removal-\(UUID().uuidString)")
    let source = folder.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(#"{"manifest_version":3,"name":"Removal fixture","version":"1","permissions":["storage"],"action":{"default_title":"starting"},"background":{"service_worker":"worker.js"}}"#.utf8)
        .write(to: source.appendingPathComponent("manifest.json"))
    try Data("""
        (async () => {
            const before = await Promise.all([browser.storage.local, browser.storage.sync, browser.storage.session]
                .map(area => area.get('marker')));
            await browser.storage.local.set({marker: 'local'});
            await browser.storage.sync.set({marker: 'sync'});
            await browser.storage.session.set({marker: 'session'});
            await browser.action.setTitle({title: before.some(area => area.marker) ? 'retained' : 'clean'});
        })();
        """.utf8).write(to: source.appendingPathComponent("worker.js"))
    let profileID = UUID()
    let host = TestHost()
    let registry = ExtensionRegistry(folder: folder.appendingPathComponent("packages"), nativeHostFolders: [], ephemeral: false) { _ in .nonPersistent() }
    registry.host = host
    let owner = registry.extensions(for: profileID)
    let candidate = try await owner.prepare(folder: source)
    var record = InstalledExtension(id: candidate.identifier, version: "1", source: .folder(source),
                                    grantedPermissions: candidate.permissions, grantedSites: candidate.sites)
    record.packageID = candidate.packageID
    host.records = [record]
    try await owner.load(record)
    defer { try? owner.unload(record.id) }
    try await waitForRemovalFixture(owner, id: record.id)
    #expect(owner.action(for: record.id)?.label == "clean")
    if unloadFirst { try owner.unload(record.id) }
    try await owner.remove(record)
    #expect(owner.contexts[record.id] == nil)
    try await owner.remove(record)
    try await owner.load(record)
    try await waitForRemovalFixture(owner, id: record.id)
    #expect(owner.action(for: record.id)?.label == "clean", "Reinstalling the same ID must not recover deleted storage")
    try await owner.remove(record)
}

@MainActor
private func waitForRemovalFixture(_ owner: ProfileExtensions, id: String) async throws {
    let deadline = ContinuousClock.now + .seconds(15)
    while owner.action(for: id)?.label == "starting", ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    try #require(owner.action(for: id)?.label != "starting", "Storage writes must finish before removal")
}
