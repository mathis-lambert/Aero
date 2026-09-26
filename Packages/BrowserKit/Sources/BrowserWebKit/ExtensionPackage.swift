import CryptoKit
import Foundation
import Security

/// Chrome Web Store packages and what Aero adds to an extension before loading it.
/// See docs/EXTENSIONS.md › Installing and › What WebKit lacks.
enum ExtensionPackage {
    enum Failure: Error, Equatable {
        case notCRX, malformedHeader, identifierMismatch, signatureMismatch, invalidManifest, unsafeEntry
    }

    static let compatibilityFile = "aero-compatibility.js"
    static let workerFile = "aero-worker.js"

    /// Chrome's identifier for a public key: the first 16 bytes of its SHA-256, written with the letters a to p.
    static func identifier(forPublicKey key: Data) -> String {
        String(SHA256.hash(data: key).prefix(16).flatMap { [$0 >> 4, $0 & 0x0f] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }

    /// An unpacked extension's identifier, as Chrome gives it: from its manifest's `key`, the public
    /// key a store package is signed with, or else from the folder's path.
    static func identifier(ofFolder folder: URL) -> String {
        let manifest = (try? Data(contentsOf: folder.appendingPathComponent("manifest.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let key = (manifest?["key"] as? String).flatMap({ Data(base64Encoded: $0) }) { return identifier(forPublicKey: key) }
        return identifier(forPublicKey: Data(folder.standardizedFileURL.path.utf8))
    }

    // MARK: - CRX3

    /// The archive of a CRX3 package, once the proof made with the key `identifier` derives from checks
    /// out. That key also signs the identifier the header claims, so a package cannot pass for another.
    static func archive(ofCRX data: Data, identifier: String) throws -> Data {
        let data = Data(data)
        guard data.count > 12, data.prefix(4) == Data("Cr24".utf8), integer(data, at: 4) == 3 else { throw Failure.notCRX }
        let headerSize = Int(integer(data, at: 8))
        guard data.count >= 12 + headerSize else { throw Failure.malformedHeader }
        let header = data.subdata(in: 12..<(12 + headerSize))
        let archive = data.subdata(in: (12 + headerSize)..<data.count)
        let fields = try protobufFields(header)
        guard let signedData = fields.first(where: { $0.number == 10000 })?.value,
              let claimedID = try protobufFields(signedData).first(where: { $0.number == 1 })?.value else { throw Failure.malformedHeader }
        let proofs: [(key: Data, signature: Data)] = try fields.filter { $0.number == 2 }.compactMap { field in
            let proof = try protobufFields(field.value)
            guard let key = proof.first(where: { $0.number == 1 })?.value, let signature = proof.first(where: { $0.number == 2 })?.value else { return nil }
            return (key, signature)
        }
        guard let (key, signature) = proofs.first(where: { Self.identifier(forPublicKey: $0.key) == identifier }),
              Data(SHA256.hash(data: key).prefix(16)) == claimedID else { throw Failure.identifierMismatch }
        var signed = Data("CRX3 SignedData\u{0}".utf8)
        withUnsafeBytes(of: UInt32(signedData.count).littleEndian) { signed.append(contentsOf: $0) }
        signed += signedData + archive
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(key as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil)
        else { throw Failure.signatureMismatch }
        return archive
    }

    private static func integer(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    /// The length-delimited fields of a protobuf message; the CRX3 header has no other kind.
    private static func protobufFields(_ data: Data) throws -> [(number: Int, value: Data)] {
        var fields: [(Int, Data)] = []
        var index = 0
        while index < data.count {
            let key = try varint(data, &index)
            let length = try varint(data, &index)
            guard key & 7 == 2, length <= data.count - index else { throw Failure.malformedHeader }
            fields.append((key >> 3, data.subdata(in: index..<(index + length))))
            index += length
        }
        return fields
    }

    private static func varint(_ data: Data, _ index: inout Int) throws -> Int {
        var value = 0
        for shift in stride(from: 0, to: 63, by: 7) {
            guard index < data.count else { throw Failure.malformedHeader }
            let byte = data[index]
            index += 1
            value |= Int(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
        }
        throw Failure.malformedHeader
    }

    // MARK: - Preparation

    /// Unpacks, prepares and puts an extension in `destination`, replacing what is there only once all of
    /// it succeeded, so a failure never leaves half an extension.
    enum Source { case archive(Data), folder(URL) }

    static func install(_ source: Source, at destination: URL) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch source {
        case .folder(let folder):
            try FileManager.default.copyItem(at: folder, to: staging)
        case .archive(let archive):
            let zip = staging.appendingPathExtension("zip")
            defer { try? FileManager.default.removeItem(at: zip) }
            try archive.write(to: zip)
            // ditto refuses entries that would land outside the folder.
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, staging.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw Failure.unsafeEntry }
        }
        try prepare(staging)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }

    /// Puts the inert declarations first in the service worker, through a worker that imports them and
    /// then the extension's own, and first in each page. Only adds files and a script tag; preparing
    /// again changes nothing. Refuses a package with a symbolic link or a worker outside the folder.
    static func prepare(_ folder: URL) throws {
        let resources = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        var pages: [URL] = []
        while let file = resources?.nextObject() as? URL {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw Failure.unsafeEntry }
            if file.pathExtension.lowercased() == "html" { pages.append(file) }
        }
        let manifestFile = folder.appendingPathComponent("manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestFile)) as? [String: Any] else { throw Failure.invalidManifest }
        try Data(compatibilityScript.utf8).write(to: folder.appendingPathComponent(compatibilityFile), options: .atomic)
        if var background = manifest["background"] as? [String: Any], let worker = background["service_worker"] as? String, worker != workerFile {
            let path = worker.hasPrefix("/") ? String(worker.dropFirst()) : worker
            guard !path.isEmpty, !path.split(separator: "/").contains("..") else { throw Failure.invalidManifest }
            let wrapper = background["type"] as? String == "module"
                ? "import '/\(compatibilityFile)';\nimport '/\(path)';\n"
                : "importScripts('/\(compatibilityFile)', '/\(path)');\n"
            try Data(wrapper.utf8).write(to: folder.appendingPathComponent(workerFile), options: .atomic)
            background["service_worker"] = workerFile
            manifest["background"] = background
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestFile, options: .atomic)
        }
        let tag = "<script src=\"/\(compatibilityFile)\"></script>"
        for page in pages {
            var html = try String(contentsOf: page, encoding: .utf8)
            guard !html.contains(compatibilityFile) else { continue }
            if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) { html.insert(contentsOf: tag, at: head.upperBound) }
            else { html = tag + html }
            try Data(html.utf8).write(to: page, options: .atomic)
        }
    }

    /// Declarations for extension APIs WebKit lacks, each made only while WebKit has none, and inert:
    /// events that never fire, settings Aero does not have, a store nothing manages.
    static let compatibilityScript = """
        (() => {
            const api = globalThis.chrome;
            if (!api) return;
            const event = () => ({ addListener() {}, removeListener() {}, hasListener: () => false, hasListeners: () => false });
            const settled = (value) => (...args) => {
                args.find((argument) => typeof argument === "function")?.(value);
                return Promise.resolve(value);
            };
            const setting = () => ({
                get: settled({ value: false, levelOfControl: "not_controllable" }), set: settled(undefined), clear: settled(undefined), onChange: event()
            });
            const define = (namespace, members) => {
                const target = api[namespace] ?? (api[namespace] = {});
                for (const [name, make] of Object.entries(members)) {
                    if (target[name] == null) Object.defineProperty(target, name, { value: make(), configurable: true });
                }
            };
            define("webNavigation", Object.fromEntries(["onBeforeNavigate", "onCommitted", "onDOMContentLoaded", "onCompleted", "onErrorOccurred",
                "onCreatedNavigationTarget", "onReferenceFragmentUpdated", "onTabReplaced", "onHistoryStateUpdated"].map((name) => [name, event])));
            define("privacy", {
                services: () => ({ passwordSavingEnabled: setting(), autofillEnabled: setting(), autofillAddressEnabled: setting(), autofillCreditCardEnabled: setting() })
            });
            define("notifications", {
                create: () => settled(""), update: () => settled(false), clear: () => settled(false), getAll: () => settled({}),
                onClicked: event, onClosed: event, onButtonClicked: event
            });
            define("storage", { managed: () => ({ get: settled({}), onChanged: event() }) });
        })();
        """
}
