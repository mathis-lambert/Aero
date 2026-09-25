import AppKit
import BrowserCore
import SwiftUI

/// The only custom key interception in the browser window. It handles the recent-tab switcher and
/// reserved commands before a focused page can claim them; every other key, including text entry,
/// IME composition and page-first shortcuts, follows the normal responder chain and menus.
@MainActor
final class KeyboardRouter {
    private static let tabKeyCode: UInt16 = 48
    private var monitor: Any?

    init(browser: @escaping @MainActor () -> BrowserModel?) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard let browser = browser(),
                  NSApp.keyWindow?.identifier?.rawValue == WindowConfiguration.mainWindowIdentifier else { return event }
            return Self.route(event, to: browser) ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Returns whether the event was consumed.
    private static func route(_ event: NSEvent, to browser: BrowserModel) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .flagsChanged {
            if !modifiers.contains(.control) { browser.commitTabCycle() }
            return false
        }
        if event.keyCode == tabKeyCode, modifiers.contains(.control), !modifiers.contains(.command), !modifiers.contains(.option),
           browser.window.commandBar == nil, !browser.window.profilesPresented {
            browser.cycleTab(backwards: modifiers.contains(.shift))
            return true
        }
        guard let command = BrowserCommand.allCases.first(where: { $0.keyRouting == .reserved && $0.shortcut?.matches(event) == true }),
              browser.isEnabled(command) else { return false }
        browser.perform(command)
        return true
    }
}

private extension KeyboardShortcut {
    static let modifierFlags: [(EventModifiers, NSEvent.ModifierFlags)] = [
        (.command, .command), (.shift, .shift), (.option, .option), (.control, .control)
    ]

    /// Compares by character, like menu key equivalents, so shortcuts follow the keyboard layout.
    func matches(_ event: NSEvent) -> Bool {
        let expected = NSEvent.ModifierFlags(Self.modifierFlags.filter { modifiers.contains($0.0) }.map(\.1))
        let relevant = NSEvent.ModifierFlags(Self.modifierFlags.map(\.1))
        return event.modifierFlags.intersection(relevant) == expected
            && event.charactersIgnoringModifiers?.lowercased() == String(key.character).lowercased()
    }
}
