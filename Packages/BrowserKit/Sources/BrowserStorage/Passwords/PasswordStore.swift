import BrowserCore
import Foundation
import Security

public enum PasswordStoreError: Error, Equatable, Sendable {
    /// The keychain is locked and cannot ask now.
    case locked
    /// The person refused, or failed, the keychain's authentication.
    case denied
    /// A username change would overwrite another login for the same site and profile.
    case duplicate
    /// The profile was deleted while an import was still running.
    case deletedProfile
    case failed(OSStatus)
}

public enum LoginSaveOutcome: Sendable, Equatable {
    case added, updated, unchanged
    /// An import met a different saved password and left it.
    case kept
}

/// Passwords in the login keychain, one internet password item per profile, origin and username.
/// Nothing else keeps them, and nothing here logs them. See docs/PASSWORDS.md › Model.
public actor PasswordStore {
    private static let creatorCode: FourCharCode = 0x4145_524F // "AERO"
    private static let testCreatorCode: FourCharCode = 0x4145_5254 // "AERT"

    private let namespace: String
    private let creator: FourCharCode
    private var deletedProfiles: Set<UUID> = []

    /// `namespace` separates release channels and test runs: the bundle identifier, or a test folder's name.
    public init(namespace: String, testing: Bool) {
        self.namespace = namespace
        creator = testing ? Self.testCreatorCode : Self.creatorCode
    }

    // MARK: - Reading

    /// The profile's logins, without passwords.
    public func logins(profileID: UUID) throws -> [SavedLogin] {
        try attributes(matching: [kSecAttrSecurityDomain as String: domain(profileID)]).compactMap { login(from: $0, profileID: profileID) }
    }

    /// One login's password, read when it is needed and never kept here.
    public func password(for login: SavedLogin) throws -> String {
        var query = identity(login.origin, username: login.username, profileID: login.profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw Self.error(status) }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Writing

    /// Adds the login, or changes its password when `replacing`; an import passes `false` to keep
    /// passwords already saved.
    @discardableResult
    public func save(_ record: LoginRecord, profileID: UUID, replacing: Bool = true) throws -> LoginSaveOutcome {
        guard !deletedProfiles.contains(profileID) else { throw PasswordStoreError.deletedProfile }
        let identity = identity(record.origin, username: record.username, profileID: profileID)
        let saved = SavedLogin(profileID: profileID, origin: record.origin, username: record.username)
        do {
            let current = try password(for: saved)
            if current == record.password { return .unchanged }
            guard replacing else { return .kept }
            try check(SecItemUpdate(identity as CFDictionary, [kSecValueData as String: Data(record.password.utf8)] as CFDictionary))
            return .updated
        } catch PasswordStoreError.failed(errSecItemNotFound) {
            var item = identity
            item[kSecValueData as String] = Data(record.password.utf8)
            item[kSecAttrLabel as String] = Self.label(record.origin, username: record.username)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            try check(SecItemAdd(item as CFDictionary, nil))
            return .added
        }
    }

    /// Changes a login's username and password. The username names the item, so a new one replaces it.
    public func update(_ login: SavedLogin, username: String, password: String) throws -> SavedLogin {
        guard username != login.username else {
            try save(LoginRecord(origin: login.origin, username: username, password: password), profileID: login.profileID)
            return login
        }
        let renamed = SavedLogin(profileID: login.profileID, origin: login.origin, username: username, lastUsed: login.lastUsed)
        do {
            _ = try self.password(for: renamed)
            throw PasswordStoreError.duplicate
        } catch PasswordStoreError.failed(errSecItemNotFound) {
            // The new identity is free; keep the old item until its replacement is saved.
        }
        try save(LoginRecord(origin: login.origin, username: username, password: password), profileID: login.profileID)
        do {
            if let lastUsed = login.lastUsed { try setLastUsed(lastUsed, of: renamed) }
            try delete(login)
        } catch {
            // The original is still present; discard the replacement so the rename can be retried.
            try? delete(renamed)
            throw error
        }
        return renamed
    }

    /// The login was just filled or signed in with; offers list it first from now on.
    public func markUsed(_ login: SavedLogin) throws { try setLastUsed(.now, of: login) }

    public func delete(_ login: SavedLogin) throws {
        let status = SecItemDelete(identity(login.origin, username: login.username, profileID: login.profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    /// Every login of the profile, for its deletion. Repeating it is harmless.
    public func removeAll(profileID: UUID) throws {
        deletedProfiles.insert(profileID)
        for login in try logins(profileID: profileID) { try delete(login) }
    }

    /// Test runs only: removes abandoned items after a day, leaving concurrent runs alone.
    public func removeItemsOfOtherTestRuns() throws {
        guard creator == Self.testCreatorCode else { return }
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        for item in try attributes(matching: [:]) {
            guard let domain = item[kSecAttrSecurityDomain as String] as? String, !domain.hasPrefix(namespace + "/"),
                  let created = item[kSecAttrCreationDate as String] as? Date, created < cutoff,
                  let server = item[kSecAttrServer as String] as? String else { continue }
            let account = item[kSecAttrAccount as String] as? String ?? ""
            var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrCreator as String: creator,
                                        kSecAttrSecurityDomain as String: domain, kSecAttrServer as String: server, kSecAttrAccount as String: account]
            if let port = item[kSecAttrPort as String] { query[kSecAttrPort as String] = port }
            if let scheme = item[kSecAttrProtocol as String] { query[kSecAttrProtocol as String] = scheme }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
        }
    }

    // MARK: - Items

    private func domain(_ profileID: UUID) -> String { "\(namespace)/\(profileID.uuidString)" }

    /// The attributes that name one item: the keychain allows one per combination.
    private func identity(_ origin: SiteOrigin, username: String, profileID: UUID) -> [String: Any] {
        let https = origin.scheme == "https"
        return [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: creator,
            kSecAttrSecurityDomain as String: domain(profileID),
            kSecAttrServer as String: origin.host,
            kSecAttrProtocol as String: https ? kSecAttrProtocolHTTPS : kSecAttrProtocolHTTP,
            kSecAttrPort as String: origin.port ?? (https ? 443 : 80),
            kSecAttrAccount as String: username
        ]
    }

    /// Attributes of every item of ours matching `extra`, without secrets: the keychain cannot list
    /// many items with their data in one call.
    private func attributes(matching extra: [String: Any]) throws -> [[String: Any]] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: creator,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        query.merge(extra) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Self.error(status) }
        return result as? [[String: Any]] ?? []
    }

    private func login(from item: [String: Any], profileID: UUID) -> SavedLogin? {
        // The keychain leaves out an empty account, as sites without a username save.
        guard let host = item[kSecAttrServer as String] as? String else { return nil }
        let account = item[kSecAttrAccount as String] as? String ?? ""
        let https = (item[kSecAttrProtocol as String] as? String) == (kSecAttrProtocolHTTPS as String)
        let port = (item[kSecAttrPort as String] as? NSNumber)?.intValue
        guard let origin = SiteOrigin(scheme: https ? "https" : "http", host: host, port: port) else { return nil }
        let lastUsed = (item[kSecAttrComment as String] as? String).flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        return SavedLogin(profileID: profileID, origin: origin, username: account, lastUsed: lastUsed)
    }

    private func setLastUsed(_ date: Date, of login: SavedLogin) throws {
        let change = [kSecAttrComment as String: String(Int(date.timeIntervalSince1970))]
        try check(SecItemUpdate(identity(login.origin, username: login.username, profileID: login.profileID) as CFDictionary, change as CFDictionary))
    }

    private static func label(_ origin: SiteOrigin, username: String) -> String {
        username.isEmpty ? origin.host : "\(origin.host) (\(username))"
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    private static func error(_ status: OSStatus) -> PasswordStoreError {
        switch status {
        case errSecInteractionNotAllowed, errSecNotAvailable: .locked
        case errSecUserCanceled, errSecAuthFailed: .denied
        default: .failed(status)
        }
    }
}
