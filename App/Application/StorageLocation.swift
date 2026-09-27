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
            #if DEBUG
            let name = "Aero Development"
            #else
            let name = "Aero"
            #endif
            data = URL.applicationSupportDirectory.appendingPathComponent(name, isDirectory: true).appendingPathComponent("Storage", isDirectory: true)
            caches = URL.cachesDirectory.appendingPathComponent(Bundle.main.bundleIdentifier ?? name, isDirectory: true)
        }
    }
}
