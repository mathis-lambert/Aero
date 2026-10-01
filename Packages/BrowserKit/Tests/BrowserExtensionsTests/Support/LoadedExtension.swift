import AppKit
import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

/// An example extension prepared and loaded as Aero loads it, with Aero's layer, for one profile of a `TestHost`.
@MainActor
final class LoadedExtension {
    let folder: URL
    let host = TestHost()
    let registry: ExtensionRegistry
    let profileID = UUID()
    let owner: ProfileExtensions
    let record: InstalledExtension
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)

    /// `files` maps package paths to their contents; the manifest's permissions are granted.
    init(manifest: String, files: [String: String] = [:], granted: [String] = []) async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "aero-extension-\(UUID())")
        let source = folder.appending(path: "source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: source.appending(path: "manifest.json"))
        for (path, contents) in files { try Data(contents.utf8).write(to: source.appending(path: path)) }
        registry = ExtensionRegistry(folder: folder.appending(path: "packages"), nativeHostFolders: [], ephemeral: true) { _ in .nonPersistent() }
        registry.host = host
        window.isReleasedWhenClosed = false
        host.mainWindow = window
        window.orderFront(nil)
        owner = registry.extensions(for: profileID)
        let candidate = try await owner.prepare(folder: source)
        var record = InstalledExtension(id: candidate.identifier, version: "1", source: .folder(source),
                                        grantedPermissions: granted, grantedSites: candidate.sites)
        record.packageID = candidate.packageID
        self.record = record
        host.records = [record]
        try await owner.load(record)
    }

    func close() {
        try? owner.unload(record.id)
        window.close()
        try? FileManager.default.removeItem(at: folder)
    }

    /// One of the extension's pages, loaded in a view of its own.
    func page(_ path: String) async throws -> WKWebView {
        let url = try #require(URL(string: "chrome-extension://\(record.id)/\(path)"))
        let view = WKWebView(frame: .zero, configuration: try #require(registry.configuration(forExtensionPage: url, inProfile: profileID)))
        view.load(URLRequest(url: url))
        try await NativeExtension.waitUntilLoaded(view)
        return view
    }
}
