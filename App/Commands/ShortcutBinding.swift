import AppKit
import SwiftUI
import WebKit

/// A layout-aware menu key equivalent, not a physical key code or a translated display label.
struct ShortcutBinding: Codable, Hashable {
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: Int
        static let command = Self(rawValue: 1)
        static let option = Self(rawValue: 2)
        static let control = Self(rawValue: 4)
        static let shift = Self(rawValue: 8)
    }

    let key: String
    let modifiers: Modifiers

    init(_ key: String, _ modifiers: Modifiers = .command) {
        // Plus and equals are the same zoom/menu key on layouts where Shift produces plus.
        self.key = key == "=" ? "+" : key == "\u{19}" ? "\t" : key.lowercased()
        self.modifiers = self.key == "+" ? modifiers.subtracting(.shift) : modifiers
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.modifierFlags.intersection([.command, .control]).isEmpty,
              let text = event.characters(byApplyingModifiers: event.modifierFlags.intersection([.command, .shift])),
              text.count == 1 else { return nil }
        var modifiers: Modifiers = []
        for (stored, native) in Self.flags where event.modifierFlags.contains(native) { modifiers.insert(stored) }
        // Shift used to produce a printable digit or punctuation belongs to the key, not the
        // shortcut modifiers (for example the number row on AZERTY). Keep Shift for letters/Tab/arrows.
        if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0xF700 && !CharacterSet.letters.contains($0) }) {
            modifiers.remove(.shift)
        }
        self.init(text, modifiers)
    }

    var isValid: Bool {
        self == Self(key, modifiers) && key.count == 1 && modifiers.rawValue & ~15 == 0 &&
            (!modifiers.intersection([.command, .control]).isEmpty)
    }

    var shortcut: KeyboardShortcut {
        var flags: EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(key.first ?? " "), modifiers: flags)
    }

    var eventModifiers: NSEvent.ModifierFlags {
        Self.flags.reduce(into: NSEvent.ModifierFlags()) { result, item in
            if modifiers.contains(item.0) { result.insert(item.1) }
        }
    }

    private static let flags: [(Modifiers, NSEvent.ModifierFlags)] = [
        (.command, .command), (.option, .option), (.control, .control), (.shift, .shift)
    ]

    @MainActor
    init?(command: WKWebExtension.Command) {
        guard let key = command.activationKey, key.count == 1 else { return nil }
        var modifiers: ShortcutBinding.Modifiers = []
        let flags = command.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(key, modifiers)
    }
}
