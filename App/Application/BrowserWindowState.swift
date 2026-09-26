import Foundation
import Observation

/// Transient presentation only; never serialized into the durable session.
@MainActor @Observable
final class BrowserWindowState {
    var selectedProfileID: UUID?
    var selectedTabID: UUID?
    var sidebarPinned = true
    /// The control bar over the selected tab; the New Tab page shows its own.
    var controlBar: ControlBarPresentation?
    var profileSheet: ProfileSheet?
    var quitPromptPresented = false
    /// Popovers on the sidebar's reload button and address; the sidebar appears for them when hidden.
    var siteSettingsPresented = false
    var controlCenterPresented = false
    /// Counts copies, so the address can confirm each one.
    var linkCopies = 0

    var holdsSidebarOpen: Bool { siteSettingsPresented || controlCenterPresented }
    /// Changes when the New Tab page or a browser page should focus its search field.
    var inputFocusRequest = UUID()
    let find = FindInPage()
}
