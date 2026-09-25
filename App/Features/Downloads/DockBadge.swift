import AppKit
import SwiftUI

extension View {
    /// Shows the number of active downloads on the Dock icon, like Safari.
    func downloadsDockBadge(activeCount: Int) -> some View {
        onChange(of: activeCount, initial: true) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? count.formatted() : nil
        }
    }
}
