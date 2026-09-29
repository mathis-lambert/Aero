import AppKit
import SwiftUI

@main
struct AeroApp: App {
    @NSApplicationDelegateAdaptor(BrowserAppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    private var browser: BrowserModel { delegate.browser }

    var body: some Scene {
        Window("Aero", id: BrowserWindowView.windowID) {
            BrowserWindowView(browser: browser)
                .browserMotionPreferences()
                .autocorrectionDisabled()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        // Startup chooses the first screen and its size before opening the window.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { content, context in
            // Without a saved frame: centered, as large as the first screen allows up to the browser's size.
            let fitting = content.sizeThatFits(.infinity)
            let preferred = BrowserWindowView.preferredSize(on: context.defaultDisplay.visibleRect.size)
            return WindowPlacement(.center, size: CGSize(width: min(fitting.width, preferred.width),
                                                         height: min(fitting.height, preferred.height)))
        }
        .onChange(of: browser.startup == .loading, initial: true) { _, loading in
            if !loading { openWindow(id: BrowserWindowView.windowID) }
        }
        .commands { BrowserMenuCommands(application: browser, quit: browser.requestQuit) }

        Window("Settings", id: SettingsView.windowID) {
            SettingsView(browser: browser)
                .browserMotionPreferences()
                .autocorrectionDisabled()
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class BrowserAppDelegate: NSObject, NSApplicationDelegate {
    /// Application-owned so startup can finish before the main window opens.
    let browser = BrowserModel()
    private var keyboardRouter: KeyboardRouter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardRouter = KeyboardRouter { [weak self] in self?.browser }
        // Startup belongs to the application lifetime, independently of open windows.
        Task { await browser.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard browser.updater.confirmRelaunchIfNeeded(activeDownloads: browser.downloads.activeCount) else {
            return .terminateCancel
        }
        Task {
            let saved = await browser.flush()
            if !saved { browser.updater.cancelRelaunch() }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
