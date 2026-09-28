import BrowserCore
import Foundation
import Testing
@testable import BrowserStorage

// docs/PASSWORDS.md › Failure modes 3, 5, 6, 7, 12, 14, 16 and 17.
// Items use the test creator and a namespace of their own, removed after each test: real passwords are never touched.

private func origin(_ text: String) throws -> SiteOrigin { try #require(URL(string: text).flatMap(SiteOrigin.init(url:))) }

@Suite(.serialized) struct PasswordStoreTests {
    /// Each test removes its own items; abandoned items are removed after a day.
    let store = PasswordStore(namespace: "app.getaero.browser.tests.\(UUID().uuidString)", testing: true)
    let personal = UUID()
    let work = UUID()

    @Test func profilesKeepTheirOwnLogins() async throws {
        try await store.removeItemsOfOtherTestRuns()
        let site = try origin("https://example.com")
        #expect(try await store.save(LoginRecord(origin: site, username: "alice", password: "one"), profileID: personal) == .added)
        #expect(try await store.save(LoginRecord(origin: site, username: "alice", password: "two"), profileID: work) == .added)
        let personalLogins = try await store.logins(profileID: personal)
        #expect(personalLogins.map(\.username) == ["alice"])
        #expect(try await store.password(for: #require(personalLogins.first)) == "one")
        #expect(try await store.password(for: #require(store.logins(profileID: work).first)) == "two")
        try await cleanUp()
    }

    @Test func aChangedPasswordUpdatesTheSameItem() async throws {
        try await store.removeItemsOfOtherTestRuns()
        let record = LoginRecord(origin: try origin("https://example.com:8443"), username: "", password: "old")
        #expect(try await store.save(record, profileID: personal) == .added)
        #expect(try await store.save(record, profileID: personal) == .unchanged)
        #expect(try await store.save(LoginRecord(origin: record.origin, username: "", password: "new"), profileID: personal) == .updated)
        let logins = try await store.logins(profileID: personal)
        #expect(logins.count == 1)
        #expect(logins.first?.origin == record.origin)
        #expect(try await store.password(for: #require(logins.first)) == "new")
        // An import keeps the saved password when it differs.
        #expect(try await store.save(LoginRecord(origin: record.origin, username: "", password: "imported"), profileID: personal, replacing: false) == .kept)
        #expect(try await store.password(for: #require(logins.first)) == "new")
        try await cleanUp()
    }

    @Test func renamingMovesTheLoginAndUseIsRecorded() async throws {
        try await store.removeItemsOfOtherTestRuns()
        let site = try origin("https://example.com")
        _ = try await store.save(LoginRecord(origin: site, username: "alice", password: "secret"), profileID: personal)
        let saved = try #require(try await store.logins(profileID: personal).first)
        #expect(saved.lastUsed == nil)
        let renamed = try await store.update(saved, username: "alice@example.com", password: "secret2")
        #expect(renamed.username == "alice@example.com")
        try await store.markUsed(renamed)
        let logins = try await store.logins(profileID: personal)
        #expect(logins.map(\.username) == ["alice@example.com"])
        #expect(logins.first?.lastUsed != nil)
        #expect(try await store.password(for: #require(logins.first)) == "secret2")
        try await cleanUp()
    }

    @Test func renamingToAnExistingAccountKeepsBothPasswords() async throws {
        try await store.removeItemsOfOtherTestRuns()
        let site = try origin("https://example.com")
        _ = try await store.save(LoginRecord(origin: site, username: "alice", password: "alice-secret"), profileID: personal)
        _ = try await store.save(LoginRecord(origin: site, username: "bob", password: "bob-secret"), profileID: personal)
        let alice = try #require(try await store.logins(profileID: personal).first { $0.username == "alice" })
        await #expect(throws: PasswordStoreError.duplicate) {
            try await store.update(alice, username: "bob", password: "replacement")
        }
        let logins = try await store.logins(profileID: personal)
        #expect(logins.count == 2)
        #expect(try await store.password(for: #require(logins.first { $0.username == "alice" })) == "alice-secret")
        #expect(try await store.password(for: #require(logins.first { $0.username == "bob" })) == "bob-secret")
        try await cleanUp()
    }

    @Test func removingAProfileRemovesOnlyItsLogins() async throws {
        try await store.removeItemsOfOtherTestRuns()
        let site = try origin("https://example.com")
        _ = try await store.save(LoginRecord(origin: site, username: "a", password: "1"), profileID: personal)
        _ = try await store.save(LoginRecord(origin: site, username: "b", password: "2"), profileID: personal)
        _ = try await store.save(LoginRecord(origin: site, username: "c", password: "3"), profileID: work)
        try await store.removeAll(profileID: personal)
        #expect(try await store.logins(profileID: personal).isEmpty)
        #expect(try await store.logins(profileID: work).map(\.username) == ["c"])
        // Removing again is harmless, as a resumed profile deletion needs.
        try await store.removeAll(profileID: personal)
        let deleted = try #require(try await store.logins(profileID: work).first)
        try await store.delete(deleted)
        #expect(try await store.logins(profileID: work).isEmpty)
        try await cleanUp()
    }

    @Test func aDeletedProfileRejectsLateImportWrites() async throws {
        try await store.removeItemsOfOtherTestRuns()
        let site = try origin("https://example.com")
        try await store.removeAll(profileID: personal)
        await #expect(throws: PasswordStoreError.deletedProfile) {
            try await store.save(LoginRecord(origin: site, username: "late", password: "secret"), profileID: personal)
        }
        #expect(try await store.logins(profileID: personal).isEmpty)
        try await cleanUp()
    }

    private func cleanUp() async throws {
        try await store.removeAll(profileID: personal)
        try await store.removeAll(profileID: work)
    }
}

@Test func chromiumPasswordsDecryptWithTheBrowserKey() throws {
    // Vector made independently with PBKDF2 (Python) and `openssl enc -aes-128-cbc`.
    let key = ChromiumLogins.derivedKey(fromSafeStorageSecret: "peanuts")
    #expect(key.map { String(format: "%02x", $0) }.joined() == "d9a09d499b4e1b7461f28e67972c6dbd")
    var blob = Data("v10".utf8)
    blob.append(contentsOf: [0xd4, 0x6c, 0x6b, 0xc6, 0x5f, 0x13, 0xcf, 0xfb, 0xbd, 0xa3, 0x2d, 0xaf, 0x1e, 0x6b, 0x8e, 0x23])
    #expect(ChromiumLogins.decrypt(blob, key: key) == "hunter2 é")
    // Another scheme or a damaged blob is reported, never returned as text.
    #expect(ChromiumLogins.decrypt(Data("v11".utf8) + blob.dropFirst(3), key: key) == nil)
    #expect(ChromiumLogins.decrypt(blob.dropLast(1), key: key) == nil)
    #expect(ChromiumLogins.decrypt(blob, key: ChromiumLogins.derivedKey(fromSafeStorageSecret: "other")) == nil)
}
