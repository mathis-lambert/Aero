import AppKit
import SwiftUI

@main
struct AeroApp: App {
    @NSApplicationDelegateAdaptor(BrowserAppDelegate.self) private var delegate
    @State private var browser = BrowserModel()

    var body: some Scene {
        Window("Aero", id: BrowserWindowView.windowID) {
            BrowserWindowView(browser: browser)
                .task {
                    delegate.browser = browser
                    await browser.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands { BrowserMenuCommands(quit: browser.requestQuit) }

        Settings {
            SettingsView(browser: browser)
        }
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
        Task { sender.reply(toApplicationShouldTerminate: await browser.flush()) }
        return .terminateLater
    }
}
