import BrowserCore
import BrowserStorage
import Foundation

/// Records a journey starts from, written through Aero's own store before launch, so a journey spends its time
/// on what it verifies rather than on clicking its way there. The session is the one a fresh launch creates.
struct Seed: Sendable {
    private static let colors = [SpaceColor(0x3366CC), SpaceColor(0x2E9D5B), SpaceColor(0x8E44AD), SpaceColor(0xD35400)]

    let server: FixtureServer
    private(set) var session = BrowserSession(profileName: "Personal", spaceName: "Main")

    init(server: FixtureServer) { self.server = server }

    var main: BrowserSpace { session.spaces[0] }

    /// A space in `profile`, created when no profile has that name; the first profile by default.
    @discardableResult
    mutating func addSpace(_ name: String, profile: String? = nil) throws -> BrowserSpace {
        let owner = if let profile {
            try session.profiles.first { $0.name == profile } ?? session.addProfile(name: profile)
        } else { session.profiles[0] }
        return try session.addSpace(name: name, profileID: owner.id, color: Self.colors[session.spaces.count % Self.colors.count])
    }

    /// A tab showing `fixture`, titled as the page is, in `space` (Main by default) at `place`.
    @discardableResult
    mutating func addTab(_ fixture: String, title: String, in space: BrowserSpace? = nil, place: TabPlace = .open) -> BrowserTab? {
        let url = server.url(fixture)
        guard let tab = session.open(url, in: (space ?? main).id) else { return nil }
        session.updateTab(id: tab.id, url: url, title: title)
        if place != .open { _ = session.move(id: tab.id, to: place, before: nil) }
        return session.tabs.first { $0.id == tab.id }
    }

    mutating func addGroup(_ name: String, in space: BrowserSpace? = nil) -> TabGroup? {
        session.addGroup(named: name, in: (space ?? main).id)
    }

    func write(to root: URL) async throws {
        let store = BrowserStore(directory: root.appendingPathComponent("Storage", isDirectory: true))
        try await store.save(session, revision: 1)
        await store.close()
    }
}
