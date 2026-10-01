import AppKit
import BrowserWebKit
import Observation

/// Shows the number of active downloads on the Dock icon, like Safari, whether or not the browser window is open.
@MainActor
final class DockBadge {
    private let downloads: DownloadCoordinator

    init(downloads: DownloadCoordinator) {
        self.downloads = downloads
        update()
    }

    private func update() {
        let count = withObservationTracking { downloads.activeCount } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? count.formatted() : nil
    }
}
