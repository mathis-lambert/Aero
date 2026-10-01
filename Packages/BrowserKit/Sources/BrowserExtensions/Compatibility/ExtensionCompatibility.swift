import Foundation

enum ExtensionCompatibility {
    /// Each compatibility file has its own scope and shares only the bootstrap's small API helpers. WebKit invariants
    /// run in every context; the missing APIs only outside content scripts, which Chrome does not give them either.
    static func script() throws -> Data {
        guard let resources = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            throw ExtensionPackage.Failure.missingCompatibilityLayer
        }
        func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
        func scripts(in directory: String, guardContentScripts: Bool = false) throws -> String {
            try FileManager.default.contentsOfDirectory(at: resources.appendingPathComponent(directory), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "js" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { "(() => {\n\(guardContentScripts ? "if (inContentScript) return;\n" : "")\(try read($0))\n})();\n" }.joined()
        }
        let permissions = String(decoding: try JSONSerialization.data(withJSONObject: ExtensionCapabilities.providedPermissions.sorted()), as: UTF8.self)
        let nativePermissions = String(decoding: try JSONSerialization.data(withJSONObject: ExtensionCapabilities.nativePermissions.sorted()), as: UTF8.self)
        let source = try read(resources.appendingPathComponent("Bootstrap.js"))
            + "const providedPermissions = new Set(\(permissions));\n"
            + "const nativePermissions = new Set(\(nativePermissions));\n"
            + read(resources.appendingPathComponent("WebKitRuntime.js"))
            + scripts(in: "APIs", guardContentScripts: true)
            + "})();\n"
        return Data(source.utf8)
    }
}
