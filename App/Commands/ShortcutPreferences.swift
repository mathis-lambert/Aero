import BrowserCore
import Foundation
import Observation
import SwiftUI

/// Only overrides are persisted. Missing = inherit, [] = disabled, nonempty = explicit bindings.
/// Unknown command IDs are retained so removing a command never rewrites unrelated preferences.
@MainActor @Observable
final class ShortcutPreferences {
    private struct Document: Codable {
        var version = 1
        var overrides: [String: [ShortcutBinding]] = [:]
        var priorities: [String: ShortcutPriority]?
    }
    private static let key = "browser.shortcuts"
    private let defaults: UserDefaults
    private var document = Document()
    private(set) var effective: [BrowserCommand: [ShortcutBinding]] = [:]
    private(set) var blocked: [BrowserCommand: [String]] = [:]
    private(set) var error: String?
    private var unreadableData: Data?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                let decoded = try JSONDecoder().decode(Document.self, from: data)
                guard decoded.version == 1, decoded.overrides.values.allSatisfy({ $0.count <= 1 && $0.allSatisfy(\.isValid) }) else {
                    throw CocoaError(.coderReadCorrupt)
                }
                document = decoded
            } catch {
                unreadableData = data
                self.error = String(localized: "Saved shortcuts could not be read. Your data has been kept. Restore defaults to continue.")
            }
        }
        resolve()
    }

    func shortcut(for command: BrowserCommand) -> KeyboardShortcut? { effective[command]?.first?.shortcut }
    func isCustomized(_ command: BrowserCommand) -> Bool {
        document.overrides[command.rawValue] != nil || document.priorities?[command.rawValue] != nil
    }

    func priority(for command: BrowserCommand) -> ShortcutPriority {
        document.priorities?[command.rawValue] ?? .automatic
    }

    func routing(for command: BrowserCommand) -> BrowserCommand.KeyRouting {
        guard command.supportsWebsitePriority else { return .reserved }
        switch priority(for: command) {
        case .automatic: return command.keyRouting
        case .browser: return .reserved
        case .website: return .pageFirst
        }
    }

    func setPriority(_ priority: ShortcutPriority, for command: BrowserCommand) {
        guard command.supportsWebsitePriority else { return }
        var next = document
        var priorities = next.priorities ?? [:]
        if priority == .automatic { priorities.removeValue(forKey: command.rawValue) }
        else { priorities[command.rawValue] = priority }
        next.priorities = priorities.isEmpty ? nil : priorities
        save(next)
    }

    func conflicts(for binding: ShortcutBinding, excluding command: BrowserCommand) -> [BrowserCommand] {
        BrowserCommand.allCases.filter { $0 != command && effective[$0, default: []].contains(binding) }
    }

    func assign(_ binding: ShortcutBinding, to command: BrowserCommand) {
        guard unreadableData == nil, binding.isValid, nativeConflict(binding, for: command) == nil else { return }
        let conflicts = conflicts(for: binding, excluding: command)
        var next = document
        for conflict in conflicts {
            next.overrides[conflict.rawValue] = effective[conflict, default: []].filter { $0 != binding }
        }
        next.overrides[command.rawValue] = [binding]
        save(next)
    }

    func disable(_ command: BrowserCommand) {
        var next = document
        next.overrides[command.rawValue] = []
        save(next)
    }

    func restore(_ command: BrowserCommand) {
        var next = document
        next.overrides.removeValue(forKey: command.rawValue)
        next.priorities?.removeValue(forKey: command.rawValue)
        save(next)
    }

    func restoreAll() {
        // Explicit recovery preserves the exact unreadable bytes before replacing them.
        if let unreadableData { defaults.set(unreadableData, forKey: Self.key + ".recovery") }
        unreadableData = nil
        save(Document())
    }

    private func save(_ next: Document) {
        guard unreadableData == nil else { return }
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: Self.key)
            document = next
            error = nil
            resolve()
        } catch { self.error = String(localized: "Shortcuts could not be saved. Please try again.") }
    }

    private func resolve() {
        var resolved: [BrowserCommand: [ShortcutBinding]] = [:]
        var owners: [ShortcutBinding: BrowserCommand] = [:]
        var blocked: [BrowserCommand: [String]] = [:]
        // Explicit choices always win over newly shipped defaults. Catalog order breaks corrupt duplicates deterministically.
        let commands = BrowserCommand.allCases
        for command in commands.filter({ document.overrides[$0.rawValue] != nil }) + commands.filter({ document.overrides[$0.rawValue] == nil }) {
            for binding in document.overrides[command.rawValue] ?? command.defaultBindings {
                if let native = nativeConflict(binding, for: command) {
                    blocked[command, default: []].append(native)
                    continue
                }
                if let owner = owners[binding], owner != command {
                    blocked[command, default: []].append(owner.title)
                } else {
                    owners[binding] = command
                    if !resolved[command, default: []].contains(binding) { resolved[command, default: []].append(binding) }
                }
            }
        }
        effective = resolved
        self.blocked = blocked
    }

    /// These continue through native menus/responder-chain editing, not browser interception.
    func nativeConflict(_ binding: ShortcutBinding, for command: BrowserCommand) -> String? {
        if binding == ShortcutBinding("w"), command != .closeTab { return String(localized: "Close Window") }
        return Self.nativeBindings[binding]
    }

    private static let nativeBindings: [ShortcutBinding: String] = [
        .init("w", [.command, .shift]): String(localized: "Close Window"),
        .init("q"): String(localized: "Quit Aero"), .init(","): String(localized: "Settings…"),
        .init("c"): String(localized: "Copy"), .init("v"): String(localized: "Paste"),
        .init("x"): String(localized: "Cut"), .init("a"): String(localized: "Select all"),
        .init("z"): String(localized: "Undo"), .init("z", [.command, .shift]): String(localized: "Redo"),
        .init("h"): String(localized: "Hide Aero"), .init("h", [.command, .option]): String(localized: "Hide others"),
        .init("m"): String(localized: "Minimize"), .init("f", [.command, .control]): String(localized: "Full screen"),
        .init("\t"): String(localized: "Switch applications"), .init("\t", [.command, .shift]): String(localized: "Switch applications"),
        .init(" "): String(localized: "Spotlight"), .init("`"): String(localized: "Switch windows")
    ]
}
