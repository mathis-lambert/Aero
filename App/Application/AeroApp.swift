import AppKit
import SwiftUI

@main
struct AeroApp: App {
    @NSApplicationDelegateAdaptor(BrowserAppDelegate.self) private var delegate
    @State private var browser = BrowserModel()

    var body: some Scene {
        Window("Aero", id: BrowserWindowView.windowID) {
            BrowserWindowView(browser: browser)
                .browserMotionPreferences()
                .autocorrectionDisabled()
                .task {
                    delegate.browser = browser
                    await browser.start()
                    if browser.onboarding == nil { browser.updater.start() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
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
    weak var browser: BrowserModel?
    private var keyboardRouter: KeyboardRouter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardRouter = KeyboardRouter { [weak self] in self?.browser }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let browser else { return .terminateNow }
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
