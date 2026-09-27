import Foundation

/// Durable records and disposable caches use the macOS locations for their distinct lifetimes.
struct StorageLocation {
    let data: URL
    let caches: URL

    init(testDirectory: URL?) {
        if let root = testDirectory {
            data = root.appendingPathComponent("Storage", isDirectory: true)
            caches = root.appendingPathComponent("Caches", isDirectory: true)
        } else {
            guard let name = Bundle.main.object(forInfoDictionaryKey: "AeroDataDirectory") as? String,
                  !name.isEmpty, !name.contains("/"), !name.contains("$(") else {
                preconditionFailure("Missing build channel storage configuration")
            }
            data = URL.applicationSupportDirectory.appendingPathComponent(name, isDirectory: true).appendingPathComponent("Storage", isDirectory: true)
            caches = URL.cachesDirectory.appendingPathComponent(Bundle.main.bundleIdentifier ?? name, isDirectory: true)
        }
    }
}
