import AppKit
import BrowserCore
import WebKit

/// What WebKit asks the browser for on an extension's behalf. See docs/EXTENSIONS.md › The browser's part.
extension ProfileExtensions: WKWebExtensionControllerDelegate {
    // MARK: - Windows

    public func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [mainWindow] + windows
    }

    public func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard NSApplication.shared.isActive, let key = NSApplication.shared.keyWindow else { return nil }
        if key === host?.mainWindow { return mainWindow }
        return windows.first { $0.window === key }
    }

    /// A popup window gets a window of its own; a normal one opens its addresses as tabs of the main window, Aero's
    /// only browser window, where the tabs it names already are. Without addresses or tabs it shows the New Tab page,
    /// as a new window would.
    public func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        guard let host else { throw ExtensionRequestFailure.unsupported("A window") }
        if configuration.shouldBePrivate { throw ExtensionRequestFailure.unsupported("A private window") }
        if configuration.windowType == .popup, !configuration.tabs.isEmpty { throw ExtensionRequestFailure.unsupported("Moving tabs into a popup window") }
        guard configuration.windowType == .popup, let url = configuration.tabURLs.first else {
            let opened = configuration.tabURLs.compactMap { host.openTab($0, inProfile: profileID, selected: false) }
            if configuration.shouldBeFocused {
                if let first = opened.first ?? configuration.tabs.compactMap({ ($0 as? BrowserTabAdapter)?.id }).first {
                    host.activateTab(first)
                } else {
                    host.showNewTab(inProfile: profileID)
                }
                try await mainWindow.focus(for: extensionContext)
            }
            return mainWindow
        }
        let pageConfiguration = extensionContext.webViewConfiguration.flatMap { url.host() == extensionContext.baseURL.host() ? $0 : nil }
            ?? host.websiteConfiguration(forProfile: profileID)
        let window = ExtensionWindow(extensionID: extensionContext.uniqueIdentifier, url: url, configuration: pageConfiguration,
                                     frame: configuration.frame, owner: self)
        windows.append(window)
        controller.didOpenWindow(window)
        controller.didOpenTab(window.tab)
        window.show(focused: configuration.shouldBeFocused)
        return window
    }

    func windowDidClose(_ window: ExtensionWindow) {
        guard windows.contains(where: { $0 === window }) else { return }
        windows.removeAll { $0 === window }
        controller.didCloseTab(window.tab, windowIsClosing: true)
        controller.didCloseWindow(window)
    }

    // MARK: - Tabs and pages

    public func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        // Without an address, Chrome opens the New Tab page: an extension's, or Aero's own, which is no tab.
        guard let url = configuration.url ?? newTabPageURL(order: host?.installedExtensions(inProfile: profileID).filter(\.isEnabled).map(\.id) ?? []) else {
            host?.showNewTab(inProfile: profileID)
            return nil
        }
        guard let tabID = host?.openTab(url, inProfile: profileID, selected: configuration.shouldBeActive) else { return nil }
        if configuration.shouldBePinned { host?.setPinned(true, tab: tabID) }
        return tab(tabID)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        guard let url = extensionContext.optionsPageURL else { return }
        _ = host?.openTab(url, inProfile: profileID, selected: true)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                       for context: WKWebExtensionContext) async throws {
        presentPopup(action, context: context)
    }

    // MARK: - Actions

    public func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                       forExtensionContext context: WKWebExtensionContext) {
        actionRevision += 1
    }

    // MARK: - Permissions

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        let granted = await host?.requestPermissions(Set(permissions.map(\.rawValue)), sites: [], for: extensionContext.uniqueIdentifier, inProfile: profileID) == true
        return (granted ? permissions : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let websites = matchPatterns.filter(ExtensionSiteAccess.permits)
        guard !websites.isEmpty else { return ([], nil) }
        let granted = await host?.requestPermissions([], sites: Set(websites.map(\.string)), for: extensionContext.uniqueIdentifier, inProfile: profileID) == true
        return (granted ? websites : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        let websites = urls.filter { !ExtensionSiteAccess.isExtensionScheme($0.scheme) }
        guard !websites.isEmpty else { return ([], nil) }
        let patterns = websites.compactMap { url -> String? in
            guard let scheme = url.scheme, let host = url.host(),
                  let pattern = try? WKWebExtension.MatchPattern(scheme: scheme, host: host, path: "/*") else { return nil }
            return pattern.string
        }
        guard patterns.count == websites.count else { return ([], nil) }
        let granted = await host?.requestPermissions([], sites: Set(patterns), for: extensionContext.uniqueIdentifier, inProfile: profileID) == true
        return (granted ? websites : [], nil)
    }

    // MARK: - Native messaging

    public func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort,
                                       for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        let extensionID = extensionContext.uniqueIdentifier
        do {
            let connection = try connect(to: port.applicationIdentifier, for: extensionID, onMessage: { port.sendMessage($0) { _ in } }) { [weak self, weak port] in
                port?.disconnect()
                if let port { self?.endSession(of: port, for: extensionID) }
            }
            port.messageHandler = { [weak port] message, error in
                guard error == nil, let message else { return }
                // A message the program cannot take ends the connection, as in Chrome.
                do { try connection.send(message) } catch { connection.close(); port?.disconnect() }
            }
            port.disconnectHandler = { [weak self, weak port] _ in
                connection.close()
                if let port { self?.endSession(of: port, for: extensionID) }
            }
            nativeSessions[extensionID, default: []].append(NativeSession(port: port, connection: connection))
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    /// One message and its reply; a program that ends without replying answers with an error.
    public func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?,
                                       for extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        var connection: NativeMessagingConnection?
        var answered = false
        let answer: (Any?, (any Error)?) -> Void = { reply, error in
            guard !answered else { return }
            answered = true
            connection?.close()
            replyHandler(reply, error)
        }
        do {
            connection = try connect(to: applicationIdentifier, for: extensionContext.uniqueIdentifier, onMessage: { answer($0, nil) }) {
                answer(nil, NativeMessagingFailure.hostEndedWithoutReply)
            }
            try connection?.send(message)
        } catch {
            answer(nil, error)
        }
    }

    /// Records what happened, so Settings can say whether the extension reaches its desktop app.
    private func connect(to name: String?, for extensionID: String, onMessage: @escaping (Any) -> Void, onClose: @escaping () -> Void) throws -> NativeMessagingConnection {
        let name = name ?? ""
        guard contexts[extensionID]?.hasPermission(.nativeMessaging) == true else {
            desktopApps[extensionID] = DesktopAppConnection(hostName: name, application: nil, state: .refused(.noPermission))
            throw NativeMessagingFailure.hostNotAllowed
        }
        guard let host = NativeMessagingHost.named(name, in: nativeHostFolders) else {
            desktopApps[extensionID] = DesktopAppConnection(hostName: name, application: nil, state: .refused(.notInstalled))
            throw NativeMessagingFailure.hostNotFound
        }
        guard host.allows(extensionID: extensionID) else {
            desktopApps[extensionID] = DesktopAppConnection(hostName: name, application: host.application, state: .refused(.notAllowed))
            throw NativeMessagingFailure.hostNotAllowed
        }
        do {
            let connection = try NativeMessagingConnection(host: host, extensionID: extensionID, onMessage: onMessage) { [weak self] in
                self?.desktopApps[extensionID] = DesktopAppConnection(hostName: name, application: host.application, state: .ended)
                onClose()
            }
            desktopApps[extensionID] = DesktopAppConnection(hostName: name, application: host.application, state: .connected)
            return connection
        } catch {
            desktopApps[extensionID] = DesktopAppConnection(hostName: name, application: host.application, state: .refused(.failedToStart))
            throw error
        }
    }

    private func endSession(of port: WKWebExtension.MessagePort, for extensionID: String) {
        nativeSessions[extensionID]?.removeAll { $0.port === port }
    }
}

/// A connected port and the host program behind it, retained while connected.
struct NativeSession {
    let port: WKWebExtension.MessagePort
    let connection: NativeMessagingConnection
}

enum NativeMessagingFailure: LocalizedError {
    case hostNotFound, hostNotAllowed, hostEndedWithoutReply

    var errorDescription: String? {
        switch self {
        case .hostNotFound: "No app on this Mac registered this native messaging host."
        case .hostNotAllowed: "The native messaging host does not allow this extension."
        case .hostEndedWithoutReply: "The native messaging host ended without replying."
        }
    }
}

/// Whether an extension reaches the desktop app it talks to, such as a password manager's.
public struct DesktopAppConnection: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case connected
        /// The app ended the connection, or the extension did.
        case ended
        case refused(Refusal)
    }

    public enum Refusal: Sendable {
        /// No app registered the host the extension asked for.
        case notInstalled
        /// The app's registration does not list this extension.
        case notAllowed
        case failedToStart
        /// The extension was not granted native messaging.
        case noPermission
    }

    public let hostName: String
    /// The app bundle holding the host program, when there is one.
    public let application: URL?
    public let state: State
}
