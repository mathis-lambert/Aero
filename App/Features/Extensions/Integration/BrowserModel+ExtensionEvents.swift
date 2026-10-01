import AppKit
import BrowserCore
import BrowserExtensions
import Foundation
import WebKit

extension BrowserModel {
    // MARK: - Tab events

    private func extensions(of tab: BrowserTab) -> ProfileExtensions? {
        profileID(of: tab).flatMap(extensions.extensionsIfMade(for:))
    }

    func extensionsDidOpen(_ tab: BrowserTab) { extensions(of: tab)?.didOpenTab(tab.id) }
    func extensionsDidClose(_ tab: BrowserTab) { extensions(of: tab)?.didCloseTab(tab.id) }
    func extensionsDidChange(_ tab: BrowserTab, _ properties: WKWebExtension.TabChangedProperties) {
        extensions(of: tab)?.didChangeTab(tab.id, properties: properties)
    }

    func extensionsDidSelect(_ tab: BrowserTab, previous: UUID?) {
        extensions(of: tab)?.didActivateTab(tab.id, previous: previous.flatMap { id in tabs.contains { $0.id == id } ? id : nil })
    }

    func extensionsDidNavigateWithinDocument(_ tab: BrowserTab, _ visit: HistoryNavigation) {
        extensions(of: tab)?.didNavigateWithinDocument(tab.id, to: visit.url, from: visit.referrer, transition: visit.transition)
    }

    func extensionsDidOpenNavigationTarget(_ tabID: UUID, from openerTabID: UUID) {
        guard let tab = tab(tabID) else { return }
        extensions(of: tab)?.didOpenNavigationTarget(tabID, from: openerTabID)
    }

    func extensionsDidMove(_ tab: BrowserTab, fromIndex index: Int?) {
        guard let index else { return }
        extensions(of: tab)?.didMoveTab(tab.id, fromIndex: index)
    }

    /// The tab's position among its profile's tabs, as extensions number them.
    func extensionIndex(of tabID: UUID) -> Int? {
        guard let tab = tab(tabID), let profileID = profileID(of: tab) else { return nil }
        return tabIDs(inProfile: profileID).firstIndex(of: tabID)
    }

    // MARK: - Commands

    /// A key press that is the shortcut of an extension's command runs it, unless Aero uses that shortcut.
    func performExtensionCommand(for event: NSEvent) -> Bool {
        guard let profileID = profile?.id, let owner = extensions.extensionsIfMade(for: profileID) else { return false }
        return owner.perform(event) { [shortcuts] command in
            ShortcutBinding(command: command).map { shortcuts.owner(of: $0) == nil } ?? false
        }
    }

    /// Applies saved shortcut overrides. Routing rejects conflicts with Aero and system shortcuts.
    func applyExtensionShortcuts(_ extensionID: String, in owner: ProfileExtensions) {
        for command in owner.commands(of: extensionID) {
            let choice = shortcuts.extensionShortcut(command: command.id, of: extensionID)
            switch choice {
            case .default: continue
            case .none: owner.setShortcut(nil, modifiers: [], forCommand: command.id, of: extensionID)
            case .binding(let binding):
                owner.setShortcut(binding.key, modifiers: binding.eventModifiers, forCommand: command.id, of: extensionID)
            }
        }
    }
}
