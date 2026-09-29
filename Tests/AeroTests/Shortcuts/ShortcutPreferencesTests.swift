@testable import Aero
import BrowserCore
import Foundation
import Testing

// docs/SHORTCUTS.md › Persistence and resolution. Written as failure modes first:
// 1. A shipped default shadows another default or a native command, so one of them silently never works.
// 2. Recording a taken shortcut leaves two owners, or the displaced default comes back after a relaunch.
// 3. A newly shipped default wins over a person's explicit choice.
// 4. Unreadable or unsupported saved data is overwritten, edited, or lost by Restore defaults.
// 5. A native shortcut (Quit, Close Window) can be assigned to a browser command.
// 6. Disabling or restoring does not last, or restoring keeps a priority override.
// 7. A command without a menu item accepts website priority, which would leave its shortcut dead.
// 8. Plus and equals, or letter case, make two identities for one key.

/// Each test gets its own preferences suite, removed when it ends.
@MainActor
final class ShortcutPreferencesTests {
    private let suite = "app.getaero.browser.unittests.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }

    private func preferences() -> ShortcutPreferences { ShortcutPreferences(defaults: defaults) }

    private func saved(_ json: String) { defaults.set(Data(json.utf8), forKey: "browser.shortcuts") }

    @Test func shippedDefaultsResolveWithoutConflicts() {
        let preferences = preferences()
        #expect(preferences.blocked.isEmpty)
        var owners: [ShortcutBinding: BrowserCommand] = [:]
        for command in BrowserCommand.allCases {
            #expect(preferences.effective[command, default: []] == command.defaultBindings, "\(command) keeps its default")
            for binding in command.defaultBindings {
                #expect(owners.updateValue(command, forKey: binding) == nil, "\(command) shares \(binding) with another default")
                #expect(preferences.nativeConflict(binding, for: command) == nil, "\(command)'s default shadows a native command")
            }
        }
    }

    @Test func recordingATakenShortcutMovesItForGood() {
        let first = preferences()
        first.assign(ShortcutBinding("t"), to: .toggleSidebar)
        #expect(first.effective[.toggleSidebar] == [ShortcutBinding("t")])
        #expect(first.effective[.newTab, default: []].isEmpty)
        #expect(first.conflicts(for: ShortcutBinding("t"), excluding: .newTab) == [.toggleSidebar])
        let relaunched = preferences()
        #expect(relaunched.effective[.toggleSidebar] == [ShortcutBinding("t")])
        #expect(relaunched.effective[.newTab, default: []].isEmpty, "The displaced default stays disabled")
        #expect(relaunched.isCustomized(.newTab))
    }

    @Test func anExplicitChoiceWinsOverADefault() {
        saved(#"{"version":1,"overrides":{"toggleSidebar":[{"key":"t","modifiers":1}],"futureCommand":[]}}"#)
        let preferences = preferences()
        #expect(preferences.effective[.toggleSidebar] == [ShortcutBinding("t")])
        #expect(preferences.effective[.newTab, default: []].isEmpty)
        #expect(preferences.blocked[.newTab] == [BrowserCommand.toggleSidebar.title], "Settings names what took the default")
        preferences.disable(.toggleSidebar)
        #expect(String(decoding: defaults.data(forKey: "browser.shortcuts")!, as: UTF8.self).contains("futureCommand"), "Unknown commands survive edits")
    }

    @Test(arguments: ["not a shortcut document", #"{"version":2,"overrides":{}}"#, #"{"version":1,"overrides":{"newTab":[{"key":"tt","modifiers":1}]}}"#])
    func unreadableDataIsKeptUntilRestoreDefaults(_ bytes: String) {
        saved(bytes)
        let preferences = preferences()
        #expect(preferences.error != nil)
        #expect(preferences.effective[.newTab] == BrowserCommand.newTab.defaultBindings, "Defaults stay usable")
        preferences.assign(ShortcutBinding("b"), to: .newTab)
        preferences.disable(.newTab)
        #expect(defaults.data(forKey: "browser.shortcuts") == Data(bytes.utf8), "Nothing edits unreadable data")
        preferences.restoreAll()
        #expect(defaults.data(forKey: "browser.shortcuts.recovery") == Data(bytes.utf8), "Restore keeps the original bytes aside")
        #expect(preferences.error == nil)
        #expect(ShortcutPreferences(defaults: defaults).error == nil)
    }

    @Test(arguments: [(ShortcutBinding("q"), BrowserCommand.toggleSidebar), (ShortcutBinding("w"), .newTab),
                      (ShortcutBinding("w", [.command, .shift]), .newTab), (ShortcutBinding(","), .reload)])
    func nativeShortcutsCannotBeAssigned(_ binding: ShortcutBinding, _ command: BrowserCommand) {
        let preferences = preferences()
        #expect(preferences.nativeConflict(binding, for: command) != nil)
        preferences.assign(binding, to: command)
        #expect(!preferences.effective[command, default: []].contains(binding))
        #expect(preferences.nativeConflict(ShortcutBinding("w"), for: .closeTab) == nil, "Close Tab owns Command-W")
    }

    @Test func disablingAndRestoringLast() {
        let first = preferences()
        first.disable(.reload)
        first.setPriority(.website, for: .reload)
        #expect(preferences().shortcut(for: .reload) == nil)
        #expect(preferences().priority(for: .reload) == .website)
        first.restore(.reload)
        let restored = preferences()
        #expect(restored.effective[.reload] == BrowserCommand.reload.defaultBindings)
        #expect(restored.priority(for: .reload) == .automatic, "Restore clears the priority too")
        #expect(!restored.isCustomized(.reload))
    }

    @Test func priorityDecidesWhoGetsAShortcutFirst() {
        let preferences = preferences()
        #expect(preferences.routing(for: .toggleSidebar) == .reserved)
        #expect(preferences.routing(for: .findInPage) == .pageFirst)
        preferences.setPriority(.website, for: .toggleSidebar)
        preferences.setPriority(.browser, for: .findInPage)
        #expect(preferences.routing(for: .toggleSidebar) == .pageFirst)
        #expect(preferences.routing(for: .findInPage) == .reserved)
    }

    @Test(arguments: [BrowserCommand.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .lastTab,
                      .recentTab, .previousRecentTab, .moveToGroup, .moveToSpace, .profiles, .newProfile,
                      .passwords, .clearCookies, .clearCache])
    func commandsWithoutAMenuItemAlwaysGoToAero(_ command: BrowserCommand) {
        let preferences = preferences()
        #expect(!command.supportsWebsitePriority)
        preferences.setPriority(.website, for: command)
        #expect(preferences.priority(for: command) == .automatic)
        #expect(preferences.routing(for: command) == .reserved, "No menu item could take \(command) from a page")
    }

    @Test func oneKeyHasOneIdentity() {
        #expect(ShortcutBinding("=") == ShortcutBinding("+"))
        #expect(ShortcutBinding("+", [.command, .shift]) == ShortcutBinding("+"))
        #expect(ShortcutBinding("T") == ShortcutBinding("t"))
        #expect(ShortcutBinding("\u{19}", [.control, .shift]) == ShortcutBinding("\t", [.control, .shift]))
        #expect(!ShortcutBinding("t", .option).isValid, "A shortcut needs Command or Control")
        #expect(!ShortcutBinding("tt").isValid)
    }
}
