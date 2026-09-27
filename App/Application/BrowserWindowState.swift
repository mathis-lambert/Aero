import AppKit
import Observation

/// Transient presentation only; never serialized into the durable session.
@MainActor @Observable
final class BrowserWindowState {
    var selectedSpaceID: UUID?
    var selectedTabID: UUID?
    var sidebarPinned = true
    var zoomFeedback: PageZoomFeedback?
    /// The control bar over the selected tab; the New Tab page shows its own.
    var controlBar: ControlBarPresentation?
    /// The question the window asks; one at a time.
    var prompt: WindowPrompt?
    /// Popovers on the sidebar's reload button and address; the sidebar appears for them when hidden.
    var downloadsPresented = false
    var tabDestination: TabMovePresentation?
    var siteSettingsPresented = false
    var controlCenterPresented = false
    /// The tab or group whose name is being edited in the sidebar.
    var renaming: RenameTarget?
    /// Counts copies, so the address can confirm each one.
    var linkCopies = 0

    /// Extension buttons on screen, for popups to hang from; keyed by extension, or `ExtensionAnchor.controlCenter`.
    @ObservationIgnored let extensionAnchors = NSMapTable<NSString, NSView>.strongToWeakObjects()

    /// Ends the edit of `target` only, so a newer one started meanwhile stays open.
    func endRenaming(_ target: RenameTarget) {
        if renaming == target { renaming = nil }
    }

    var holdsSidebarOpen: Bool { siteSettingsPresented || controlCenterPresented || downloadsPresented || renaming != nil }
    /// Changes when the New Tab page or a browser page should focus its search field.
    var inputFocusRequest = UUID()
    var settingsRoute = SettingsRoute.section(.general)
    var settingsRequest = UUID()
    let find = FindInPage()
}

enum RenameTarget: Equatable {
    case tab(UUID)
    case group(UUID)
}

/// Everything the browser asks the person, each shown by one `Prompt` over the window.
/// See docs/DESIGN.md › Prompts.
enum WindowPrompt: Identifiable {
    case quit
    case profile
    case space(UUID?)
    case removeSpace(UUID)
    case transferTab(UUID, UUID)
    /// Carries the History page's own clearing, which then reloads it.
    case clearHistory((HistoryClearRange) -> Void)
    /// Shown in the Settings window when asked from there.
    case extensionRequest(ExtensionRequest)
    case error(String)

    var id: String {
        switch self {
        case .quit: "quit"
        case .space(let target): "space.\(target?.uuidString ?? "new")"
        case .removeSpace(let id): "removeSpace.\(id)"
        case .transferTab(let id, _): "transferTab.\(id)"
        case .profile: "profile"
        case .clearHistory: "clearHistory"
        case .extensionRequest(let request): "extension.\(request.id)"
        case .error(let message): "error.\(message)"
        }
    }

    var isInSettings: Bool {
        if case .extensionRequest(let request) = self { request.inSettings } else { false }
    }
}
