import BrowserWebKit
import Foundation

@MainActor
func makeTestDownloads() -> DownloadCoordinator {
    DownloadCoordinator(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                        fallbackFilename: "Download")
}
