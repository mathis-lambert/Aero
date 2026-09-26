import CryptoKit
import Foundation
import JavaScriptCore
import Security
import Testing
@testable import BrowserWebKit

// Failure modes 1, 2 and 9 in docs/EXTENSIONS.md. Packages are signed here the way the Chrome Web Store
// signs them, with a fresh RSA key.

private struct SignedPackage {
    let crx: Data
    let identifier: String
    let archive: Data
}

/// A CRX3 file: `Cr24`, version 3, a header with one RSA proof and the signed data, then the archive.
private func package(archive: Data = Data("PK archive".utf8), identifierOverride: Data? = nil) throws -> SignedPackage {
    let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
    let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
    let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
    let pkcs1 = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
    // SubjectPublicKeyInfo around an RSA 2048 key, as Chrome stores and hashes it.
    let spki = Data([0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
                     0x03, 0x82, 0x01, 0x0f, 0x00]) + pkcs1
    let crxID = identifierOverride ?? Data(SHA256.hash(data: spki).prefix(16))
    let signedData = field(1, crxID)
    var signed = Data("CRX3 SignedData\u{0}".utf8)
    signed += littleEndian(UInt32(signedData.count)) + signedData + archive
    let signature = try #require(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, nil) as Data?)
    let header = field(2, field(1, spki) + field(2, signature)) + field(10000, signedData)
    let crx = Data("Cr24".utf8) + littleEndian(3) + littleEndian(UInt32(header.count)) + header + archive
    return SignedPackage(crx: crx, identifier: ExtensionPackage.identifier(forPublicKey: spki), archive: archive)
}

private func field(_ number: Int, _ bytes: Data) -> Data { varint(number << 3 | 2) + varint(bytes.count) + bytes }

private func varint(_ value: Int) -> Data {
    var value = value, bytes = Data()
    repeat {
        var byte = UInt8(value & 0x7f)
        value >>= 7
        if value > 0 { byte |= 0x80 }
        bytes.append(byte)
    } while value > 0
    return bytes
}

private func littleEndian(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

@Test func aSignedPackageYieldsItsArchive() throws {
    let signed = try package()
    #expect(signed.identifier.count == 32 && signed.identifier.allSatisfy { ("a"..."p").contains($0) })
    #expect(try ExtensionPackage.archive(ofCRX: signed.crx, identifier: signed.identifier) == signed.archive)
}

@Test func anAlteredArchiveIsRefused() throws {
    var signed = try package()
    signed = SignedPackage(crx: signed.crx.dropLast() + Data([0x00]), identifier: signed.identifier, archive: signed.archive)
    #expect(throws: ExtensionPackage.Failure.signatureMismatch) { try ExtensionPackage.archive(ofCRX: signed.crx, identifier: signed.identifier) }
}

@Test func aPackageSignedForAnotherIdentifierIsRefused() throws {
    let signed = try package()
    #expect(throws: ExtensionPackage.Failure.identifierMismatch) {
        try ExtensionPackage.archive(ofCRX: signed.crx, identifier: String(repeating: "a", count: 32))
    }
    let claimsAnother = try package(identifierOverride: Data(repeating: 0, count: 16))
    #expect(throws: ExtensionPackage.Failure.identifierMismatch) {
        try ExtensionPackage.archive(ofCRX: claimsAnother.crx, identifier: claimsAnother.identifier)
    }
}

@Test func whatIsNotACRX3PackageIsRefused() throws {
    let signed = try package()
    for data in [Data(), Data("PK\u{3}\u{4}zip".utf8), signed.crx.prefix(20), Data("Cr24".utf8) + littleEndian(2) + littleEndian(0)] {
        #expect(throws: ExtensionPackage.Failure.self) { try ExtensionPackage.archive(ofCRX: data, identifier: signed.identifier) }
    }
}

// MARK: - Preparation

private func extensionFolder(manifest: String, files: [String: String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-extension-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
    for (path, text) in files {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    return folder
}

private func text(_ folder: URL, _ path: String) throws -> String {
    try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
}

@Test func theInertScriptRunsBeforeAClassicWorker() throws {
    let folder = try extensionFolder(manifest: #"{"manifest_version": 3, "name": "A", "version": "1", "background": {"service_worker": "bg/main.js"}}"#,
                                     files: ["bg/main.js": "self.ran = true;"])
    try ExtensionPackage.prepare(folder)
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any]
    let worker = try #require((manifest?["background"] as? [String: Any])?["service_worker"] as? String)
    #expect(try text(folder, worker) == "importScripts('/\(ExtensionPackage.compatibilityFile)', '/bg/main.js');\n")
    #expect(try text(folder, "bg/main.js") == "self.ran = true;", "The extension's own files are not changed")
}

@Test func theInertScriptRunsBeforeAModuleWorkerAndEachPageOnce() throws {
    let folder = try extensionFolder(
        manifest: #"{"manifest_version": 3, "name": "A", "version": "1", "background": {"service_worker": "main.js", "type": "module"}}"#,
        files: ["main.js": "export {};", "popup/popup.html": "<!doctype html><html><head><title>P</title></head><body></body></html>"])
    try ExtensionPackage.prepare(folder)
    try ExtensionPackage.prepare(folder)
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any]
    let worker = try #require((manifest?["background"] as? [String: Any])?["service_worker"] as? String)
    #expect(try text(folder, worker) == "import '/\(ExtensionPackage.compatibilityFile)';\nimport '/main.js';\n")
    let page = try text(folder, "popup/popup.html")
    #expect(page.components(separatedBy: ExtensionPackage.compatibilityFile).count == 2, "Prepared once, however often it is asked")
    #expect(page.range(of: ExtensionPackage.compatibilityFile)!.lowerBound < page.range(of: "<title>")!.lowerBound)
}

@Test func aWorkerOutsideTheExtensionIsRefused() throws {
    let folder = try extensionFolder(manifest: #"{"manifest_version": 3, "name": "A", "version": "1", "background": {"service_worker": "../escape.js"}}"#,
                                     files: [:])
    #expect(throws: ExtensionPackage.Failure.self) { try ExtensionPackage.prepare(folder) }
}

@Test func aSymbolicLinkIsRefused() throws {
    let folder = try extensionFolder(manifest: #"{"manifest_version": 3, "name": "A", "version": "1"}"#, files: [:])
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc"))
    #expect(throws: ExtensionPackage.Failure.self) { try ExtensionPackage.prepare(folder) }
}

@Test func theInertScriptOnlyFillsWhatIsMissing() throws {
    let context = try #require(JSContext())
    context.evaluateScript("""
        const native = { addListener() { globalThis.nativeUsed = true; } };
        globalThis.chrome = { webNavigation: { onCompleted: native, onCreatedNavigationTarget: undefined } };
        """)
    context.evaluateScript(ExtensionPackage.compatibilityScript)
    context.evaluateScript("chrome.webNavigation.onCompleted.addListener(() => {}); chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});")
    #expect(context.exception == nil)
    #expect(context.evaluateScript("globalThis.nativeUsed === true").toBool(), "WebKit's own API is kept")
    #expect(context.evaluateScript("typeof chrome.webNavigation.onCreatedNavigationTarget.addListener").toString() == "function")
    #expect(context.evaluateScript("chrome.storage.managed.onChanged !== undefined").toBool())
}
