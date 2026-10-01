import SwiftUI

/// A dedicated native window owns the traffic lights, navigation toolbar and resizing.
struct SettingsView: View {
    private static let historyLimit = 32
    let browser: BrowserModel
    @State private var history: [SettingsRoute] = [.section(.general)]
    @State private var historyIndex = 0

    private var route: SettingsRoute { history[historyIndex] }
    private var section: SettingsSection { route.section }
    private var prompt: WindowPrompt? { browser.window.prompt.flatMap { $0.isInSettings ? $0 : nil } }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsSection?>(get: { section }, set: { if let section = $0 { navigate(to: .section(section)) } })) {
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
                switch route {
                case .profile(let id): ProfileSettingsDetail(browser: browser, profileID: id, navigate: navigate)
                case .space(let id): SpaceSettingsDetail(browser: browser, spaceID: id)
                case .passwordProfile(let id): PasswordProfileSettingsView(browser: browser, profileID: id, navigate: navigate)
                case .passwordLogin(let login): PasswordLoginSettingsView(browser: browser, login: login, replaceRoute: replaceCurrentRoute, didDelete: leaveDeletedPassword)
                case .passwordImport(let id): PasswordImportSettingsView(browser: browser, profileID: id, navigate: navigate)
                case .extension(let profileID, let extensionID):
                    ExtensionSettingsDetail(browser: browser, profileID: profileID, extensionID: extensionID)
                case .section(let section):
                    switch section {
                    case .updates: UpdateSettingsView(browser: browser)
                    case .general: GeneralSettingsView(browser: browser)
                    case .tabs: PerformanceSettingsView(browser: browser)
                    case .profiles: ProfilesSettingsView(browser: browser, navigate: navigate)
                    case .spaces: SpacesSettingsView(browser: browser, navigate: navigate)
                    case .passwords: PasswordsSettingsView(browser: browser, navigate: navigate)
                    case .extensions: ExtensionsSettingsView(browser: browser, navigate: navigate)
                    case .storage: StorageSettingsView(browser: browser, navigate: navigate)
                    case .shortcuts: ShortcutSettingsView(browser: browser)
                    }
                }
            }
            .id(route)
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
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
        .onAppear { navigate(to: browser.window.settingsRoute) }
        .onChange(of: browser.window.settingsRequest) { navigate(to: browser.window.settingsRoute) }
        .onChange(of: browser.session.spaces.map(\.id)) { pruneHistory() }
        .onChange(of: browser.profiles.map(\.id)) { pruneHistory() }
        .onChange(of: browser.session.profiles.flatMap { $0.extensions.filter { !$0.isRemoving }.map(\.id) }) { pruneHistory() }
        .onChange(of: browser.window.settingsRoute) { _, route in navigate(to: route) }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 960, height: 620)
        .windowMinimizeBehavior(.disabled)
        .windowResizeBehavior(.disabled)
        .windowFullScreenBehavior(.disabled)
        .prompt(prompt, onCancel: browser.dismissPrompt) { WindowPromptView(browser: browser, prompt: $0) }
    }

    private var title: String {
        switch route {
        case .section(let section): section.title
        case .profile(let id): browser.profiles.first { $0.id == id }?.name ?? String(localized: "Profiles")
        case .space(let id): browser.session.spaces.first { $0.id == id }?.name ?? String(localized: "Spaces")
        case .passwordProfile(let id): browser.profiles.first { $0.id == id }?.name ?? String(localized: "Passwords")
        case .passwordLogin(let login): login.origin.host
        case .passwordImport: String(localized: "Import passwords")
        case .extension(let profileID, let extensionID):
            browser.extensions.extensionsIfMade(for: profileID)?.contexts[extensionID]?.webExtension.displayName ?? String(localized: "Extensions")
        }
    }

    /// Deleted records must not leave empty detail pages in Back/Forward history.
    private func pruneHistory() {
        let current = route
        let precedingCount = history.prefix(historyIndex + 1).filter(isValid).count
        history = history.filter(isValid)
        if history.isEmpty { history = [.section(current.section)] }
        historyIndex = max(0, precedingCount - 1)
        if !isValid(current) { navigate(to: .section(current.section)) }
    }

    private func isValid(_ route: SettingsRoute) -> Bool {
        switch route {
        case .section: true
        case .profile(let id): browser.profiles.contains { $0.id == id }
        case .space(let id): browser.session.spaces.contains { $0.id == id }
        case .passwordProfile(let id), .passwordImport(let id): browser.profiles.contains { $0.id == id }
        case .passwordLogin(let login): browser.profiles.contains { $0.id == login.profileID }
        case .extension(let profileID, let extensionID): browser.installedExtension(extensionID, inProfile: profileID) != nil
        }
    }

    private func navigate(to route: SettingsRoute) {
        guard route != self.route else { return }
        history = Array(history.prefix(historyIndex + 1))
        history.append(route)
        if history.count > Self.historyLimit { history.removeFirst() }
        historyIndex = history.count - 1
    }

    private func replaceCurrentRoute(with route: SettingsRoute) {
        history[historyIndex] = route
    }

    private func leaveDeletedPassword(profileID: UUID) {
        history = Array(history.prefix(historyIndex))
        historyIndex = history.count - 1
        if history.isEmpty { history = [.passwordProfile(profileID)]; historyIndex = 0 }
        else { navigate(to: .passwordProfile(profileID)) }
    }
}
