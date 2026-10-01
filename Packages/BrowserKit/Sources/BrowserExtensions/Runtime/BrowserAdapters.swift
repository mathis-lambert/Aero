import AppKit
import BrowserCore
import WebKit

/// Why Aero refused what an extension asked; the message reaches the extension's script, not the person.
enum ExtensionRequestFailure: LocalizedError {
    case tabUnavailable, notLoaded, mainWindowStays, unsupported(String)

    var errorDescription: String? {
        switch self {
        case .tabUnavailable: "The tab is no longer available."
        case .notLoaded: "The tab's page is not loaded."
        case .mainWindowStays: "Aero's window cannot be closed or minimized by an extension."
        case .unsupported(let what): "\(what) is not supported in Aero."
        }
    }
}

/// One of the profile's tabs in the main window, as WebKit presents it to extensions. It holds the tab's identifier
/// only; every answer is read from the host, so a closed tab answers as gone. A hibernated tab has no view, so its
/// record answers where WebKit's defaults would read a web view.
final class BrowserTabAdapter: NSObject, WKWebExtensionTab {
    let id: UUID
    unowned let owner: ProfileExtensions

    init(id: UUID, owner: ProfileExtensions) {
        self.id = id
        self.owner = owner
    }

    private var host: ExtensionHost? { owner.host }
    private var webView: WKWebView? { host?.webView(forTab: id) }

    private func requireTab() throws -> ExtensionHost {
        guard let host, host.tab(id) != nil else { throw ExtensionRequestFailure.tabUnavailable }
        return host
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { host?.tab(id) == nil ? nil : owner.mainWindow }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { host?.tabIDs(inProfile: owner.profileID).firstIndex(of: id) ?? NSNotFound }
    func title(for context: WKWebExtensionContext) -> String? { host?.tab(id)?.title }
    func url(for context: WKWebExtensionContext) -> URL? { host?.tab(id)?.url }
    func isPinned(for context: WKWebExtensionContext) -> Bool { host?.tab(id)?.isFavorite == true }
    func isSelected(for context: WKWebExtensionContext) -> Bool { host?.selectedTabID(inProfile: owner.profileID) == id }
    /// A hibernated tab has no view; WebKit then reports it without one.
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { webView?.isLoading != true }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(webView?.pageZoom ?? 1) }
    func size(for context: WKWebExtensionContext) -> CGSize { webView?.bounds.size ?? .zero }

    func activate(for context: WKWebExtensionContext) async throws { try requireTab().activateTab(id) }
    func setSelected(_ selected: Bool, for context: WKWebExtensionContext) async throws {
        // One tab is selected at a time: selecting is activating; deselecting the selected tab has nothing to fall back to.
        if selected { try requireTab().activateTab(id) }
    }
    func close(for context: WKWebExtensionContext) async throws { try requireTab().removeTab(id) }
    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { try requireTab().load(url, inTab: id) }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws { try requireTab().reloadTab(id, fromOrigin: fromOrigin) }
    func goBack(for context: WKWebExtensionContext) async throws { try requireTab().goBack(inTab: id) }
    func goForward(for context: WKWebExtensionContext) async throws { try requireTab().goForward(inTab: id) }
    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws { try requireTab().setPinned(pinned, tab: id) }
    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws { try requireTab().setZoom(zoomFactor, tab: id) }

    func duplicate(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        guard let copy = try requireTab().copyTab(id) else { throw ExtensionRequestFailure.tabUnavailable }
        return owner.tab(copy)
    }

    func snapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext) async throws -> NSImage? {
        guard let webView else { throw ExtensionRequestFailure.notLoaded }
        return try await webView.takeSnapshot(configuration: configuration)
    }

    /// The language the page declares for itself.
    func detectWebpageLocale(for context: WKWebExtensionContext) async throws -> Locale? {
        guard let webView else { throw ExtensionRequestFailure.notLoaded }
        let language = try await webView.callAsyncJavaScript("return document.documentElement.lang", contentWorld: .defaultClient) as? String
        return language.flatMap { $0.isEmpty ? nil : Locale(identifier: $0) }
    }
}

/// Aero's main window, holding the profile's tabs, as WebKit presents it to extensions.
final class MainWindowAdapter: NSObject, WKWebExtensionWindow {
    unowned let owner: ProfileExtensions

    init(owner: ProfileExtensions) { self.owner = owner }

    private var window: NSWindow? { owner.host?.mainWindow }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        (owner.host?.tabIDs(inProfile: owner.profileID) ?? []).map(owner.tab)
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        owner.host?.selectedTabID(inProfile: owner.profileID).map(owner.tab)
    }

    func frame(for context: WKWebExtensionContext) -> CGRect { window?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.screen?.frame ?? NSScreen.main?.frame ?? .null }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return window.isZoomed ? .maximized : .normal
    }

    func setWindowState(_ state: WKWebExtension.WindowState, for context: WKWebExtensionContext) async throws {
        guard let window else { return }
        switch state {
        case .minimized: throw ExtensionRequestFailure.mainWindowStays
        case .fullscreen: if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        case .maximized: if !window.isZoomed { window.zoom(nil) }
        case .normal:
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            else if window.isZoomed { window.zoom(nil) }
        @unknown default: break
        }
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext) async throws {
        window?.setFrame(frame, display: true, animate: false)
    }

    func focus(for context: WKWebExtensionContext) async throws {
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close(for context: WKWebExtensionContext) async throws { throw ExtensionRequestFailure.mainWindowStays }
}
