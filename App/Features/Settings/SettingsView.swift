import AppKit
import BrowserCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, tabs, profiles

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .tabs: "Tabs"
        case .profiles: "Profiles"
        }
    }

    var symbol: String {
        switch self {
        case .general: "macwindow"
        case .tabs: "square.on.square"
        case .profiles: "person.crop.circle"
        }
    }
}

struct SettingsView: View {
    static let windowID = "aero.settings"
    /// Room around the card for its shadow: the window itself is transparent.
    private static let shadowMargin: CGFloat = 44
    private static let sidebarWidth: CGFloat = 190
    private static let segmentHeight: CGFloat = 26
    private static let segmentMinimumWidth: CGFloat = 52
    private static let segmentInset: CGFloat = 3

    let browser: BrowserModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var section: SettingsSection = .general
    @State private var managingProfiles = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Hairline(axis: .vertical)

            VStack(alignment: .leading, spacing: 16) {
                Text(section.title)
                    .font(BrowserDesign.Typography.title)
                    .padding(.top, 24)

                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                        switch section {
                        case .general: general
                        case .tabs: PerformanceSettingsView(browser: browser)
                        case .profiles: profiles
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.raised)
        }
        .font(BrowserDesign.Typography.chrome)
        .foregroundStyle(palette.ink)
        .frame(minWidth: 760, idealWidth: 780, minHeight: 500, idealHeight: 540)
        .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.window))
        .panelShadow()
        .padding(Self.shadowMargin)
        .background(SettingsWindowSurface())
        .sheet(isPresented: $managingProfiles) { ProfilesView(browser: browser) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconButton(symbol: "xmark", label: "Close settings", size: BrowserDesign.navigationButtonSize) {
                    dismissWindow(id: Self.windowID)
                }
                .accessibilityIdentifier("settings.close")

                Text("Settings")
                    .font(BrowserDesign.Typography.chrome.weight(.semibold))
            }
            .padding(.top, 18)
            .padding(.bottom, 20)

            ForEach(SettingsSection.allCases) { item in
                let selected = section == item
                Button { section = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .fontWeight(selected ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: BrowserDesign.tabRowHeight)
                        .padding(.horizontal, BrowserDesign.rowInset)
                        .foregroundStyle(selected ? palette.ink : palette.secondary)
                        .background(selected ? palette.raised : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                        .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.\(item.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .padding(.bottom, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: Self.sidebarWidth)
        .background(palette.canvas)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow("Language", caption: "Choose the language used by the browser.") {
                        Picker("Language", selection: Binding(get: { browser.preferences.language }, set: { browser.preferences.setLanguage($0) })) {
                            ForEach(BrowserLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsLayout.pickerWidth)
                        .accessibilityIdentifier("settings.language")
                    }

                    if browser.preferences.needsLanguageRestart {
                        Text("Reopen the browser to apply the language change.")
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                            .accessibilityIdentifier("settings.languageRestart")
                    }

                    SettingsDivider()

                    SettingsRow("Appearance", caption: "Choose how the browser looks.") {
                        appearancePicker
                    }
                }
            }

            SettingsCard { search }

            SettingsCard { AppIconPicker(browser: browser) }
        }
    }

    private var search: some View {
        let preferences = Bindable(browser.preferences)
        return VStack(spacing: 0) {
            SettingsRow("Search engine", caption: "Where searches from the control bar go.") {
                Picker("Search engine", selection: preferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in Text(verbatim: engine.name).tag(engine) }
                }
                .labelsHidden()
                .frame(width: SettingsLayout.pickerWidth)
                .accessibilityIdentifier("settings.searchEngine")
            }
            SettingsDivider()
            SettingsRow("Search suggestions", caption: "Shows the engine's suggestions as you type. Addresses are never sent.") {
                Toggle("Search suggestions", isOn: preferences.searchSuggestions)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.searchSuggestions")
            }
        }
    }

    private var appearancePicker: some View {
        HStack(spacing: 2) {
            ForEach([BrowserAppearance.light, .dark, .system]) { option in
                let selected = browser.preferences.appearance == option
                Button { browser.preferences.appearance = option } label: {
                    Text(option.label)
                        .font(BrowserDesign.Typography.label)
                        .fontWeight(selected ? .semibold : .regular)
                        .frame(minWidth: Self.segmentMinimumWidth)
                        .frame(height: Self.segmentHeight)
                        .padding(.horizontal, Self.segmentInset)
                        .background(selected ? palette.raised : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control - Self.segmentInset))
                        .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control - Self.segmentInset))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.theme.\(option.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Self.segmentInset)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
    }

    private var profiles: some View {
        SettingsCard {
            SettingsRow("Your profiles", caption: "Keep website sign-ins and tabs separate.") {
                Button("Manage profiles") { managingProfiles = true }
                    .accessibilityIdentifier("settings.manageProfiles")
            }
        }
    }
}

private struct SettingsWindowSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SurfaceView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SurfaceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
        }
    }
}
