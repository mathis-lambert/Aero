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
    var siteSettingsPresented = false
    var controlCenterPresented = false
    /// The quick portrait popover on the address (docs/PORTRAIT.md › Quick capture).
    var portrait: PortraitStudio?
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

    var holdsSidebarOpen: Bool {
        siteSettingsPresented || controlCenterPresented || downloadsPresented || portrait != nil || renaming != nil
    }
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
    /// `onCreated` runs once the profile is saved; asked from Settings, it shows there.
    case profile(inSettings: Bool = false, onCreated: ((UUID) -> Void)? = nil)
    case space(UUID?)
    case removeSpace(UUID, inSettings: Bool = false)
    case moveTab(TabMovePresentation)
    case transferTab(UUID, UUID)
    /// Carries the History page's own clearing, which then reloads it.
    case clearHistory((HistoryClearRange) -> Void)
    /// Shown in the Settings window when asked from there.
    case extensionRequest(ExtensionRequest)
    case applicationLink(ApplicationLink)
    case confirmation(Confirmation)
    /// A page's `alert`, `confirm` or `prompt`, for the selected tab.
    case pageDialog(PageDialogRequest)
    case error(String)
    /// The studio framing a capture of the selected page (docs/PORTRAIT.md).
    case portrait(PortraitStudio)

    var id: String {
        switch self {
        case .quit: "quit"
        case .space(let target): "space.\(target?.uuidString ?? "new")"
        case .removeSpace(let id, _): "removeSpace.\(id)"
        case .moveTab(let move): "moveTab.\(move.tabID)"
        case .transferTab(let id, _): "transferTab.\(id)"
        case .profile: "profile"
        case .clearHistory: "clearHistory"
        case .extensionRequest(let request): "extension.\(request.id)"
        case .applicationLink(let link): "applicationLink.\(link.tabID).\(link.url.absoluteString)"
        case .confirmation(let confirmation): "confirmation.\(confirmation.id)"
        case .pageDialog(let request): "pageDialog.\(request.id)"
        case .error(let message): "error.\(message)"
        case .portrait(let studio): "portrait.\(studio.id)"
        }
    }

    var isInSettings: Bool {
        switch self {
        case .extensionRequest(let request): request.inSettings
        case .confirmation(let confirmation): confirmation.inSettings
        case .profile(let inSettings, _), .removeSpace(_, let inSettings): inSettings
        default: false
        }
    }
}
