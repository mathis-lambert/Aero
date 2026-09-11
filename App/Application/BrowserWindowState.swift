import Foundation
import Observation

/// Transient presentation only; never serialized into the durable session.
@MainActor @Observable
final class BrowserWindowState {
    var selectedProfileID: UUID?
    var selectedTabID: UUID?
    var sidebarPinned = true
    var commandBar: CommandBarRequest?
    var profilesPresented = false
    var newTabFocusID = UUID()
}
