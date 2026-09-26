import BrowserCore
import Foundation
import os

public actor SessionStore {
    package enum Failure: Error { case unsupportedVersion }

    private struct Document: Codable {
        static let currentVersion = 1
        var version = currentVersion
        let session: BrowserSession
    }

    private struct PendingSave {
        let session: BrowserSession
        let revision: UInt64
    }

    private static let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.storage)
    private let file: URL
    private let coalescingDelay: Duration
    private var latestRevision: UInt64 = 0
    private var pending: PendingSave?

    private static let coalescingDelay = Duration.seconds(1)

    public init(directory: URL) {
        self.init(directory: directory, coalescingDelay: Self.coalescingDelay)
    }

    package init(directory: URL, coalescingDelay: Duration) {
        file = directory.appendingPathComponent("session.json")
        self.coalescingDelay = coalescingDelay
    }

    public func load() throws -> BrowserSession? {
        let interval = Self.signposter.beginInterval(Diagnostics.Signpost.sessionLoad)
        defer { Self.signposter.endInterval(Diagnostics.Signpost.sessionLoad, interval) }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        // Read the version before decoding the current schema. Unknown data stays untouched.
        struct Header: Decodable { let version: Int }
        guard try JSONDecoder().decode(Header.self, from: data).version == Document.currentVersion else {
            throw Failure.unsupportedVersion
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        try document.session.validate()
        return document.session
    }

    /// Writes at most once per coalescing delay; later snapshots replace pending ones.
    /// The first caller of a burst waits and reports the write failure, if any.
    public func scheduleSave(_ session: BrowserSession, revision: UInt64) async throws {
        guard revision > max(latestRevision, pending?.revision ?? 0) else { return }
        let isWaiting = pending != nil
        pending = PendingSave(session: session, revision: revision)
        guard !isWaiting else { return }
        try await Task.sleep(for: coalescingDelay)
        guard let pending else { return }
        try write(pending.session, revision: pending.revision)
    }

    public func save(_ session: BrowserSession, revision: UInt64) throws {
        try write(session, revision: revision)
    }

    private func write(_ session: BrowserSession, revision: UInt64) throws {
        guard revision >= latestRevision else { return }
        if let pending, pending.revision <= revision { self.pending = nil }
        let interval = Self.signposter.beginInterval(Diagnostics.Signpost.sessionWrite)
        defer { Self.signposter.endInterval(Diagnostics.Signpost.sessionWrite, interval) }
        try session.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(Document(session: session))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        latestRevision = revision
    }
}
