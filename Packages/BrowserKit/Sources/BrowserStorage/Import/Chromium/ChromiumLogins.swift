import BrowserCore
import CommonCrypto
import Foundation
import Security

public struct ImportedLogins: Sendable {
    public let logins: [LoginRecord]
    /// Sites the browser was told never to save for.
    public let neverSaved: [SiteOrigin]
    /// Rows whose password could not be decrypted or whose address is not a website.
    public let skipped: Int
}

public enum ChromiumLoginsError: Error, Equatable, Sendable {
    /// macOS did not hand over the browser's key: the person refused, or the browser has none.
    case keyUnavailable
    case unreadable
}

/// Reads the passwords of Chrome and the browsers built on it. See docs/PASSWORDS.md › Import and export.
public enum ChromiumLogins {
    private static let loginFile = "Login Data"

    /// Profiles of installed browsers that have a password database, with their displayed names.
    public static func installedProfiles(in applicationSupport: URL) -> [ChromiumProfile] {
        ChromiumBrowser.all.flatMap { $0.profiles(in: applicationSupport) }
            .filter { FileManager.default.fileExists(atPath: $0.file(loginFile).path) }
    }

    /// Reads and decrypts the profile's passwords. macOS asks once for the browser's key. Blocking:
    /// call it off the main actor.
    public static func read(_ profile: ChromiumProfile) throws -> ImportedLogins {
        let key = derivedKey(fromSafeStorageSecret: try safeStorageSecret(for: profile.browser))
        let rows: [(address: String, username: String, password: Data, never: Bool)]
        do {
            rows = try SourceFiles.database(profile.file(loginFile)) { database in
                try database.query("SELECT origin_url, username_value, password_value, blacklisted_by_user FROM logins") {
                    ($0.text(0), $0.text(1), $0.blob(2), $0.integer(3) != 0)
                }
            }
        } catch { throw ChromiumLoginsError.unreadable }
        var logins: [LoginRecord] = [], never: [SiteOrigin] = [], skipped = 0
        for row in rows {
            guard let origin = SiteOrigin(address: row.address) else { skipped += 1; continue }
            if row.never { never.append(origin); continue }
            guard let password = decrypt(row.password, key: key), !password.isEmpty else { skipped += 1; continue }
            logins.append(LoginRecord(origin: origin, username: row.username, password: password))
        }
        return ImportedLogins(logins: logins, neverSaved: Array(Set(never)), skipped: skipped)
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
            throw ChromiumLoginsError.keyUnavailable
        }
        return secret
    }
}
