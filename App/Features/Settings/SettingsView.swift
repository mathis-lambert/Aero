import SwiftUI

/// A dedicated native window owns the traffic lights, navigation toolbar and resizing.
struct SettingsView: View {
    static let windowID = "settings"
    private static let historyLimit = 32
    let browser: BrowserModel
    @State private var history: [SettingsSection] = [.general]
    @State private var historyIndex = 0

    private var section: SettingsSection { history[historyIndex] }
    private var prompt: WindowPrompt? { browser.window.prompt.flatMap { $0.isInSettings ? $0 : nil } }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsSection?>(get: { section }, set: { if let section = $0 { navigate(to: section) } })) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        .accessibilityIdentifier("settings.section.\(section.rawValue)")
                }
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(180)
            .accessibilityIdentifier("settings.sidebar")
        } detail: {
            Group {
                switch section {
                case .general: GeneralSettingsView(browser: browser)
                case .tabs: PerformanceSettingsView(browser: browser)
                case .profiles: ProfilesSettingsView(browser: browser)
                case .extensions: ExtensionsSettingsView(browser: browser)
                case .shortcuts: ShortcutSettingsView(shortcuts: browser.shortcuts)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(section.title)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Previous settings page", systemImage: "chevron.backward") { historyIndex -= 1 }
                        .disabled(historyIndex == 0)
                        .accessibilityIdentifier("settings.back")
                    Button("Next settings page", systemImage: "chevron.forward") { historyIndex += 1 }
                        .disabled(historyIndex == history.count - 1)
                        .accessibilityIdentifier("settings.forward")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 960, height: 620)
        .windowMinimizeBehavior(.disabled)
        .windowResizeBehavior(.disabled)
        .windowFullScreenBehavior(.disabled)
        .prompt(prompt, onCancel: browser.dismissPrompt) { WindowPromptView(browser: browser, prompt: $0) }
    }

    private func navigate(to section: SettingsSection) {
        guard section != self.section else { return }
        history = Array(history.prefix(historyIndex + 1))
        history.append(section)
        if history.count > Self.historyLimit { history.removeFirst() }
        historyIndex = history.count - 1
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, tabs, profiles, extensions, shortcuts
    var id: Self { self }
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .tabs: String(localized: "Tabs")
        case .profiles: String(localized: "Profiles")
        case .extensions: String(localized: "Extensions")
        case .shortcuts: String(localized: "Shortcuts")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .profiles: "person.crop.circle"
        case .extensions: "puzzlepiece.extension"
        case .shortcuts: "keyboard"
        }
    }
}
