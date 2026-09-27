import AppKit
import BrowserCore
import SwiftUI

/// Reserved browser actions and the MRU gesture run before WebKit. Page-first actions stay in menus.
@MainActor
final class KeyboardRouter {
    private var monitor: Any?
    private var cycleModifiers: NSEvent.ModifierFlags = []

    init(browser: @escaping @MainActor () -> BrowserModel?) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let browser = browser() else { return event }
            guard NSApp.keyWindow?.identifier?.rawValue == WindowConfiguration.mainWindowIdentifier,
                  NSApp.keyWindow?.attachedSheet == nil else {
                endCycle(browser)
                return event
            }
            return route(event, to: browser) ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
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
        // Native text composition and Escape dismissal always keep their normal responder behavior.
        if let input = NSApp.keyWindow?.firstResponder as? NSTextInputClient, input.hasMarkedText() { return false }
        guard let binding = ShortcutBinding(event: event),
              let command = BrowserCommand.allCases.first(where: {
                  browser.shortcuts.routing(for: $0) == .reserved && browser.shortcuts.effective[$0, default: []].contains(binding)
              }), browser.isEnabled(command) else { return false }
        if command == .recentTab || command == .previousRecentTab {
            guard browser.window.controlBar == nil, browser.window.renaming == nil else { return false }
            cycleModifiers = binding.eventModifiers.subtracting(.shift)
            browser.cycleTab(backwards: command == .previousRecentTab)
        } else {
            endCycle(browser)
            browser.perform(command)
        }
        return true
    }
}
