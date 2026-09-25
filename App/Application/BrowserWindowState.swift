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
    /// Changes when the new tab page or a browser page should focus its search field.
    var inputFocusRequest = UUID()
    let find = FindInPage()
}
