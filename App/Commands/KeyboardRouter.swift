import AppKit
import BrowserCore
import SwiftUI

/// Reserved browser actions and the MRU gesture run before WebKit. Page-first actions stay in menus.
@MainActor
final class KeyboardRouter {
    private var monitor: Any?
    private var cycleModifiers: NSEvent.ModifierFlags = []
    private var observers: [NSObjectProtocol] = []

    init(browser: @escaping @MainActor () -> BrowserModel?) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let browser = browser() else { return event }
            guard NSApp.keyWindow?.identifier?.rawValue == WindowConfiguration.mainWindowIdentifier,
                  NSApp.keyWindow?.attachedSheet == nil else {
                cancelCycle(browser)
                return event
            }
            return route(event, to: browser) ? nil : event
        }
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let browser = browser() { self?.cancelCycle(browser) }
                }
            })
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func cancelCycle(_ browser: BrowserModel) {
        cycleModifiers = []
        browser.window.tabCycle = nil
    }

    private func endCycle(_ browser: BrowserModel) {
        guard !cycleModifiers.isEmpty else { return }
        cycleModifiers = []
        browser.commitTabCycle()
    }

    private func route(_ event: NSEvent, to browser: BrowserModel) -> Bool {
        if event.type == .flagsChanged {
            if !event.modifierFlags.isSuperset(of: cycleModifiers) { endCycle(browser) }
            return false
        }
        // Composition keeps its native handling, including Escape.
        if let input = NSApp.keyWindow?.firstResponder as? NSTextInputClient, input.hasMarkedText() {
            cancelCycle(browser)
            return false
        }
        if browser.window.tabCycle != nil {
            switch event.keyCode {
            case 53: cancelCycle(browser); return true // Escape leaves the original page and its focus untouched.
            case 36, 76: endCycle(browser); return true
            case 123: browser.cycleTab(backwards: NSApp.userInterfaceLayoutDirection != .rightToLeft); return true
            case 124: browser.cycleTab(backwards: NSApp.userInterfaceLayoutDirection == .rightToLeft); return true
            case 126: browser.cycleTab(backwards: true); return true
            case 125: browser.cycleTab(backwards: false); return true
            default: break
            }
        }
        // Extensions' commands come after Aero's own reserved shortcuts and before the page.
        // A shortcut may serve a command of each scope; the one that applies now acts.
        guard let binding = ShortcutBinding(event: event),
              let command = BrowserCommand.allCases.first(where: {
                  browser.shortcuts.routing(for: $0) == .reserved && browser.shortcuts.effective[$0, default: []].contains(binding)
                      && browser.isEnabled($0)
              }) else {
            if browser.window.tabCycle != nil { cancelCycle(browser) }
            return browser.performExtensionCommand(for: event)
        }
        // The onboarding shows the gesture instead of switching the tabs behind it.
        if command == .recentTab || command == .previousRecentTab, browser.onboarding == nil {
            guard browser.window.controlBar == nil, browser.window.renaming == nil else { return false }
            cycleModifiers = binding.eventModifiers.subtracting(.shift)
            browser.cycleTab(backwards: command == .previousRecentTab)
            if cycleModifiers.isEmpty { browser.commitTabCycle() }
        } else {
            cancelCycle(browser)
            browser.perform(command)
        }
        return true
    }
}
