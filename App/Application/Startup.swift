import BrowserStorage
import Foundation

/// What the main window can show. Startup leaves `loading` once, before the window opens; only a retry or a
/// restoration leaves `failed` (docs/ONBOARDING.md › Presentation).
enum Startup: Equatable {
    /// Records are being opened; the window has not opened yet.
    case loading
    /// Records are loaded and the onboarding, if any, is chosen.
    case ready
    case failed(StorageFailure)
}

/// Why saved records could not be opened, and whether the launch snapshot may replace them (docs/STORAGE.md › Recovery).
struct StorageFailure: Equatable {
    let message: String
    let canRestore: Bool
}

extension StorageFailure {
    init(_ error: any Error, store: BrowserStore) async {
        switch error as? StorageError {
        case .newerVersion:
            self.init(message: String(localized: "This data requires a newer version of Aero. Your files have been kept unchanged."), canRestore: false)
        case .inUse:
            self.init(message: String(localized: "Another Aero process is using this data. Quit it, then retry."), canRestore: false)
        default:
            self.init(message: String(localized: "Your saved data could not be opened. Your files have been kept for recovery."),
                      canRestore: await store.hasRecoverySnapshot())
        }
    }
}
