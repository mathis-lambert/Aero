import AppKit
import SwiftUI

@main
struct LightBrowserApp: App {
    @NSApplicationDelegateAdaptor(BrowserAppDelegate.self) private var delegate
    @State private var browser = BrowserModel()

    var body: some Scene {
        Window("LightBrowser", id: "browser") {
            BrowserWindowView(browser: browser)
                .task {
                    delegate.browser = browser
                    await browser.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands { BrowserMenuCommands() }

        Settings {
            SettingsView(browser: browser)
                .preferredColorScheme(browser.session.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class BrowserAppDelegate: NSObject, NSApplicationDelegate {
    weak var browser: BrowserModel?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let browser = self?.browser,
                  NSApp.keyWindow?.identifier?.rawValue == WindowConfiguration.mainWindowIdentifier else { return event }
            if event.type == .flagsChanged, !event.modifierFlags.contains(.control) {
                browser.commitTabCycle()
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.type == .keyDown, event.keyCode == 48,
               modifiers.contains(.control), !modifiers.contains(.command), !modifiers.contains(.option),
               browser.window.commandBar == nil, !browser.window.profilesPresented {
                browser.cycleTab(backwards: modifiers.contains(.shift))
                return nil
            }
            return event
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let browser else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await browser.flush()) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }
}
