import Foundation
import Testing
@testable import BrowserStorage

// Failure modes: importing unclassified open/group tabs; unsafe or repeated URLs; losing source order;
// merging distinct identities by equal/truncated names; unbounded input; treating malformed data as empty success.
struct DiaImportTests {
    private let limits = ImportLimits(since: .distantPast, links: 2, pages: 0, visitsPerPage: 0)

    @Test func importsOnlyExplicitFavoritesInSourceOrder() throws {
        let data = Data(#"{"spaces":[{"name":"Work","index":2,"tabs":[]},{"name":"Personal","index":1,"tabs":[{"title":" Mail ","url":"https://mail.example/","pinned":true},{"title":"Folder tab or open tab","url":"https://open.example/","pinned":false},{"title":"Internal","url":null,"pinned":true}]}]}"#.utf8)
        let profiles = try DiaImport.read(data, limits: limits)
        #expect(profiles.map(\.name) == ["Personal", "Work"])
        #expect(profiles.map(\.id) == ["dia-space:1", "dia-space:2"])
        #expect(profiles.flatMap(\.spaces).map(\.position) == [0, 1])
        let space = try #require(profiles.first?.spaces.first)
        #expect(space.tiles.map(\.title) == ["Mail"])
        #expect(space.tiles.map(\.url.absoluteString) == ["https://mail.example/"])
        #expect(space.groups.isEmpty && space.links.isEmpty && space.color == nil)
        #expect(profiles.allSatisfy { $0.history.pages.isEmpty })
    }

    @Test func filtersUnsafeDuplicatesAndExcessFavorites() throws {
        let tabs: [[String: Any]] = ["file:///tmp/private", "javascript:alert(1)", "https://a.example/", "https://a.example/", "https://b.example/", "https://c.example/"].map { ["title": "Tab", "url": $0, "pinned": true] }
        let data = try JSONSerialization.data(withJSONObject: ["spaces": [["name": "Space", "index": 1, "tabs": tabs]]])
        let space = try #require(DiaImport.read(data, limits: limits).first?.spaces.first)
        #expect(space.tiles.map(\.url.absoluteString) == ["https://a.example/", "https://b.example/"])
        #expect(space.skipped == 3)
    }

    @Test func equalNamesDoNotMergeIdentities() throws {
        let spaces: [[String: Any]] = [1, 2].map { ["name": String(repeating: "W", count: 50), "index": $0, "tabs": []] }
        let profiles = try DiaImport.read(JSONSerialization.data(withJSONObject: ["spaces": spaces]), limits: limits)
        #expect(Set(profiles.map(\.name)).count == 2)
        #expect(profiles.allSatisfy { $0.name.count <= 40 })
    }

    @Test func aGeneratedProfileNameDoesNotCollideWithAnExistingSpaceName() throws {
        let spaces: [[String: Any]] = ["Work", "Work", "Work (1)"].enumerated().map {
            ["name": $0.element, "index": $0.offset + 1, "tabs": []]
        }
        let profiles = try DiaImport.read(JSONSerialization.data(withJSONObject: ["spaces": spaces]), limits: limits)
        #expect(Set(profiles.map(\.name)).count == 3)
        #expect(profiles[2].name == "Work (1)")
        #expect(profiles.flatMap(\.spaces).compactMap(\.name) == ["Work", "Work", "Work (1)"])
    }

    @Test(arguments: ["{}", "{\"spaces\":[]}", "{\"spaces\":[{\"name\":\" \",\"index\":1,\"tabs\":[]}]}", "{\"spaces\":[{\"name\":\"A\",\"index\":0,\"tabs\":[]}]}", "{\"spaces\":[{\"name\":\"A\",\"index\":1,\"tabs\":[]},{\"name\":\"B\",\"index\":1,\"tabs\":[]}]}"])
    func rejectsInvalidSnapshots(_ json: String) {
        #expect(throws: BrowserImportError.unreadable) { try DiaImport.read(Data(json.utf8), limits: limits) }
    }

    @Test func rejectsOversizedSnapshots() {
        #expect(throws: BrowserImportError.unreadable) { try DiaImport.read(Data(repeating: 32, count: 8 * 1024 * 1024 + 1), limits: limits) }
    }
}
