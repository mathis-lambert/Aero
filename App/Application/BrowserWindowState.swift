import AppKit
import Observation

/// Transient presentation only; never serialized into the durable session.
@MainActor @Observable
final class BrowserWindowState {
    var selectedProfileID: UUID?
    var selectedTabID: UUID?
    var sidebarPinned = true
    /// The control bar over the selected tab; the New Tab page shows its own.
    var controlBar: ControlBarPresentation?
    /// The question the window asks; one at a time.
    var prompt: WindowPrompt?
    /// Popovers on the sidebar's reload button and address; the sidebar appears for them when hidden.
    var siteSettingsPresented = false
    var controlCenterPresented = false
    /// Counts copies, so the address can confirm each one.
    var linkCopies = 0

    /// Extension buttons on screen, for popups to hang from; keyed by extension, or `ExtensionAnchor.controlCenter`.
    @ObservationIgnored let extensionAnchors = NSMapTable<NSString, NSView>.strongToWeakObjects()

    var holdsSidebarOpen: Bool { siteSettingsPresented || controlCenterPresented }
    /// Changes when the New Tab page or a browser page should focus its search field.
    var inputFocusRequest = UUID()
    let find = FindInPage()
}

/// Everything the browser asks the person, each shown by one `Prompt` over the window.
/// See docs/DESIGN.md › Prompts.
enum WindowPrompt: Identifiable {
    case quit
    case profile(ProfileTarget)
    /// Carries the History page's own clearing, which then reloads it.
    case clearHistory((HistoryClearRange) -> Void)
    /// Shown in the Settings window when asked from there.
    case extensionRequest(ExtensionRequest)
    case error(String)

    var id: String {
        switch self {
        case .quit: "quit"
        case .profile(let target): "profile.\(target)"
        case .clearHistory: "clearHistory"
        case .extensionRequest(let request): "extension.\(request.id)"
        case .error(let message): "error.\(message)"
        }
    }

    var isInSettings: Bool {
        if case .extensionRequest(let request) = self { request.inSettings } else { false }
    }
}
