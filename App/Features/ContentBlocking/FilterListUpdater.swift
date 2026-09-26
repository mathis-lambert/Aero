import BrowserCore
import BrowserStorage
import BrowserWebKit
import Foundation
import os

/// Keeps ad blocking's lists current: at launch the newest of the bundled and downloaded copies,
/// then, once a day while the app runs, newer ones if both lists download and compile.
/// See docs/SITE_CONTROLS.md › Ad and tracker blocking.
@MainActor
final class FilterListUpdater {
    struct Source: Sendable {
        let name: String
        let url: URL
    }

    static let sources = [
        Source(name: "easylist", url: URL(string: "https://easylist.to/easylist/easylist.txt")!),
        Source(name: "easyprivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!)
    ]
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let retryDelay = Duration.seconds(60 * 60)
    private static let requestTimeout: TimeInterval = 60
    private static let resourceTimeout: TimeInterval = 300
    private static let logger = Logger(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.contentBlocking)

    private let sources: [Source]
    /// Test runs start from nothing and download only from the fixture server.
    private let usesBundledLists: Bool
    private let blocker: ContentBlocker
    private let store: FilterListStore
    private let preferences: BrowserPreferences
    private let session: URLSession
    /// Only the versions stay in memory; the lists themselves are read again when an update needs them.
    private var versions: [String: Int] = [:]
    private var task: Task<Void, Never>?

    init(blocker: ContentBlocker, store: FilterListStore, preferences: BrowserPreferences, testSource: URL?) {
        sources = testSource.map { [Source(name: "test", url: $0)] } ?? Self.sources
        usesBundledLists = testSource == nil
        self.blocker = blocker
        self.store = store
        self.preferences = preferences
        session = .anonymous(requestTimeout: Self.requestTimeout, resourceTimeout: Self.resourceTimeout)
    }

    isolated deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        await installSavedLists()
        while !Task.isCancelled {
            if let checked = preferences.filterListsCheckedAt, Date.now.timeIntervalSince(checked) < Self.checkInterval {
                let remaining = Self.checkInterval - Date.now.timeIntervalSince(checked)
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                continue
            }
            if await update() { preferences.filterListsCheckedAt = .now }
            else { do { try await Task.sleep(for: Self.retryDelay) } catch { return } }
        }
    }

    /// In its own function, so the lists' text is released once they are compiled.
    private func installSavedLists() async {
        let lists = await savedLists()
        guard !lists.isEmpty, await install(lists) else { return }
        versions = lists.mapValues(\.version)
    }

    /// Downloads every list; only a complete set, with at least one newer list, replaces the lists in use.
    private func update() async -> Bool {
        var newer: [String: FilterList] = [:]
        for source in sources {
            guard let list = await download(source.url) else { return false }
            if list.version > versions[source.name] ?? 0 { newer[source.name] = list }
        }
        guard !newer.isEmpty else { return true }
        let candidate = await savedLists().merging(newer) { $1 }
        guard await install(candidate) else { return false }
        versions = candidate.mapValues(\.version)
        for (name, list) in newer {
            // The lists in use are already compiled; a copy that fails to save is downloaded again next launch.
            do { try await store.save(list, named: name) }
            catch { Self.logger.error("Could not save the \(name, privacy: .public) filter list: \(error.localizedDescription, privacy: .public)") }
        }
        return true
    }

    private func install(_ lists: [String: FilterList]) async -> Bool {
        do {
            try await blocker.install(sources.compactMap { lists[$0.name] })
            return true
        } catch {
            Self.logger.error("Could not compile the filter lists: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// A failed download keeps the lists in use; the check is retried later.
    private func download(_ url: URL) async -> FilterList? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return FilterList(text: String(decoding: data, as: UTF8.self))
    }

    /// The newest of the downloaded and bundled copy of each list.
    private func savedLists() async -> [String: FilterList] {
        let names = sources.map(\.name)
        let bundled = usesBundledLists ? await Task.detached(priority: .utility) { Self.bundledLists(names) }.value : [:]
        var lists: [String: FilterList] = [:]
        for name in names {
            let downloaded = await store.list(named: name)
            lists[name] = [downloaded, bundled[name]].compactMap { $0 }.max { $0.version < $1.version }
        }
        return lists
    }

    private nonisolated static func bundledLists(_ names: [String]) -> [String: FilterList] {
        var lists: [String: FilterList] = [:]
        for name in names {
            guard let file = Bundle.main.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            lists[name] = FilterList(text: text)
        }
        return lists
    }
}
