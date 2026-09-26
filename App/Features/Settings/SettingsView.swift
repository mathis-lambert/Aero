import BrowserCore
import SwiftUI

/// The native Settings window: a tab per section, each a grouped form.
struct SettingsView: View {
    private static let size = CGSize(width: 600, height: 520)

    let browser: BrowserModel

    /// An extension request asked from here shows here.
    private var prompt: WindowPrompt? { browser.window.prompt.flatMap { $0.isInSettings ? $0 : nil } }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView(browser: browser) }
            Tab("Tabs", systemImage: "square.on.square") { PerformanceSettingsView(browser: browser) }
            Tab("Profiles", systemImage: "person.crop.circle") { ProfilesSettingsView(browser: browser) }
            Tab("Extensions", systemImage: "puzzlepiece.extension") { ExtensionsSettingsView(browser: browser) }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
        .prompt(prompt, onCancel: browser.dismissPrompt) { WindowPromptView(browser: browser, prompt: $0) }
    }
}

private struct GeneralSettingsView: View {
    let browser: BrowserModel

    var body: some View {
        let preferences = Bindable(browser.preferences)
        Form {
            Section {
                Picker("Language", selection: Binding(get: { browser.preferences.language }, set: { browser.preferences.setLanguage($0) })) {
                    ForEach(BrowserLanguage.allCases) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("settings.language")
                if browser.preferences.needsLanguageRestart {
                    Text("Reopen the browser to apply the language change.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.languageRestart")
                }
                Picker("Appearance", selection: Binding(get: { browser.preferences.appearance }, set: browser.setAppearance)) {
                    ForEach([BrowserAppearance.light, .dark, .system]) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
            }
            Section {
                Picker("Search engine", selection: preferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                .accessibilityIdentifier("settings.searchEngine")
                Toggle(isOn: preferences.searchSuggestions) {
                    Text("Search suggestions")
                    Text("Shows the engine's suggestions as you type. Addresses are never sent.")
                }
                .accessibilityIdentifier("settings.searchSuggestions")
            }
            Section {
                Toggle(isOn: Binding(get: { browser.preferences.blocksAds }, set: browser.setBlocksAds)) {
                    Text("Block ads and trackers")
                    Text("Uses EasyList and EasyPrivacy, © The EasyList authors, under CC BY-SA 3.0. A site can be allowed from its controls.")
                }
                .accessibilityIdentifier("settings.blocksAds")
                Toggle(isOn: preferences.automaticPictureInPicture) {
                    Text("Automatic picture in picture")
                    Text("A playing video moves to a floating window when you switch tabs, and comes back with its tab.")
                }
                .accessibilityIdentifier("settings.automaticPictureInPicture")
            }
            Section {
                Toggle(isOn: preferences.confirmsQuit) {
                    Text("Ask before quitting")
                    Text("⌘Q asks for confirmation, so a stray shortcut never closes your tabs.")
                }
                .accessibilityIdentifier("settings.confirmsQuit")
            }
            Section {
                AppIconPicker(browser: browser)
            } header: {
                Text("App icon")
            } footer: {
                Text("Shown in the Dock, the Finder and Launchpad, even while Aero is closed.")
            }
        }
    }
}
