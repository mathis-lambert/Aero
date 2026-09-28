import BrowserCore
import CommonCrypto
import Foundation
import Security

/// A Chromium browser whose saved passwords Aero can import.
public struct ChromiumBrowser: Hashable, Sendable {
    public let name: String
    /// Under ~/Library/Application Support.
    let folder: String
    /// The keychain item holding the key its passwords are encrypted with.
    let service: String
    let account: String

    public static let all = [
        ChromiumBrowser(name: "Google Chrome", folder: "Google/Chrome", service: "Chrome Safe Storage", account: "Chrome"),
        ChromiumBrowser(name: "Arc", folder: "Arc/User Data", service: "Arc Safe Storage", account: "Arc"),
        ChromiumBrowser(name: "Dia", folder: "Dia/User Data", service: "Dia Safe Storage", account: "Dia"),
        ChromiumBrowser(name: "Brave", folder: "BraveSoftware/Brave-Browser", service: "Brave Safe Storage", account: "Brave"),
        ChromiumBrowser(name: "Microsoft Edge", folder: "Microsoft Edge", service: "Microsoft Edge Safe Storage", account: "Microsoft Edge"),
        ChromiumBrowser(name: "Vivaldi", folder: "Vivaldi", service: "Vivaldi Safe Storage", account: "Vivaldi")
    ]
}

/// One profile of a Chromium browser, with saved passwords.
public struct ChromiumProfile: Identifiable, Hashable, Sendable {
    public let browser: ChromiumBrowser
    /// The name the browser shows for the profile.
    public let name: String
    let folder: URL

    public var id: String { folder.path }
}

public struct ChromiumImport: Sendable {
    public let logins: [LoginRecord]
    /// Sites the browser was told never to save for.
    public let neverSaved: [SiteOrigin]
    /// Rows whose password could not be decrypted or whose address is not a website.
    public let skipped: Int
}

public enum ChromiumImportError: Error, Equatable, Sendable {
    /// macOS did not hand over the browser's key: the person refused, or the browser has none.
    case keyUnavailable
    case unreadable
}

/// Reads the passwords of Chrome and the browsers built on it. See docs/PASSWORDS.md › Import and export.
public enum ChromiumLogins {
    private static let loginFile = "Login Data"

    /// Profiles of installed browsers that have a password database, with their displayed names.
    public static func installedProfiles(in applicationSupport: URL = .applicationSupportDirectory) -> [ChromiumProfile] {
        ChromiumBrowser.all.flatMap { browser -> [ChromiumProfile] in
            let root = applicationSupport.appendingPathComponent(browser.folder, isDirectory: true)
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
            let names = profileNames(in: root)
            return children
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(loginFile).path) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { ChromiumProfile(browser: browser, name: names[$0.lastPathComponent] ?? $0.lastPathComponent, folder: $0) }
        }
    }

    /// Reads and decrypts the profile's passwords. macOS asks once for the browser's key. Blocking:
    /// call it off the main actor.
    public static func read(_ profile: ChromiumProfile) throws -> ChromiumImport {
        let key = derivedKey(fromSafeStorageSecret: try safeStorageSecret(for: profile.browser))
        // The browser keeps its database locked while it runs; a copy reads as it was last written.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("aero-logins-\(UUID().uuidString)")
        defer {
            for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: copy.path + suffix)) }
        }
        let source = profile.folder.appendingPathComponent(loginFile)
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            for suffix in ["-wal", "-journal"] where FileManager.default.fileExists(atPath: source.path + suffix) {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: source.path + suffix), to: URL(fileURLWithPath: copy.path + suffix))
            }
        } catch { throw ChromiumImportError.unreadable }
        let rows: [(address: String, username: String, password: Data, never: Bool)]
        do {
            let database = try SQLiteDatabase(file: copy, readOnly: true)
            rows = try database.query("SELECT origin_url, username_value, password_value, blacklisted_by_user FROM logins") {
                ($0.text(0), $0.text(1), $0.blob(2), $0.integer(3) != 0)
            }
        } catch { throw ChromiumImportError.unreadable }
        var logins: [LoginRecord] = [], never: [SiteOrigin] = [], skipped = 0
        for row in rows {
            guard let origin = SiteOrigin(address: row.address) else { skipped += 1; continue }
            if row.never { never.append(origin); continue }
            guard let password = decrypt(row.password, key: key), !password.isEmpty else { skipped += 1; continue }
            logins.append(LoginRecord(origin: origin, username: row.username, password: password))
        }
        return ChromiumImport(logins: logins, neverSaved: Array(Set(never)), skipped: skipped)
    }

    /// Chromium's recipe on macOS: PBKDF2 over SHA-1, the salt "saltysalt", 1003 rounds, 16 bytes.
    static func derivedKey(fromSafeStorageSecret secret: String) -> [UInt8] {
        let password = Array(secret.utf8), salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.map { CChar(bitPattern: $0) }, password.count,
                                 salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        return key
    }

    /// "v10", then AES-128-CBC with PKCS#7 padding and an IV of sixteen spaces; `nil` for anything else.
    static func decrypt(_ blob: Data, key: [UInt8]) -> String? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else { return nil }
        let ciphertext = Array(blob.dropFirst(3))
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else { return nil }
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var length = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, ciphertext, ciphertext.count, &plaintext, plaintext.count, &length)
        guard status == kCCSuccess else { return nil }
        return String(bytes: plaintext.prefix(length), encoding: .utf8)
    }

    /// The browser's key, from its keychain item: macOS asks the person before handing it over.
    private static func safeStorageSecret(for browser: ChromiumBrowser) throws -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: browser.service,
            kSecAttrAccount as String: browser.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw ChromiumImportError.keyUnavailable
        }
        return secret
    }

    /// `profile.info_cache` in the browser's Local State: folder name to displayed name.
    private static func profileNames(in root: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }
}
