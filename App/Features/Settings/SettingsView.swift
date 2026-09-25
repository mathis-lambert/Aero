import AppKit
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

    let browser: BrowserModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var section: SettingsSection = .general
    @State private var managingProfiles = false
    @Environment(\.colorScheme) private var scheme

    private var colors: SettingsColors { SettingsColors(scheme: scheme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(colors.border)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 16) {
                Text(section.title)
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.top, 24)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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
            .background(colors.canvas)
        }
        .font(.system(size: 14))
        .foregroundStyle(colors.ink)
        .frame(minWidth: 760, idealWidth: 780, minHeight: 500, idealHeight: 540)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.14), radius: 36, y: 12)
        .padding(44)
        .background(SettingsWindowSurface())
        .sheet(isPresented: $managingProfiles) { ProfilesView(browser: browser) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { dismissWindow(id: Self.windowID) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(colors.control, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Close settings")
                .accessibilityLabel("Close settings")
                .accessibilityIdentifier("settings.close")

                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.top, 18)
            .padding(.bottom, 20)

            ForEach(SettingsSection.allCases) { item in
                let selected = section == item
                Button { section = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 36)
                        .padding(.horizontal, 11)
                        .foregroundStyle(selected ? colors.ink : colors.secondary)
                        .background(selected ? colors.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.\(item.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .padding(.bottom, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 190)
        .background(colors.sidebar)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                            .font(.system(size: 11))
                            .foregroundStyle(colors.secondary)
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

            SettingsCard { AppIconPicker(browser: browser) }
        }
    }

    private var appearancePicker: some View {
        HStack(spacing: 2) {
            ForEach([BrowserAppearance.light, .dark, .system]) { option in
                let selected = browser.preferences.appearance == option
                Button { browser.preferences.appearance = option } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .frame(minWidth: 52)
                        .frame(height: 26)
                        .padding(.horizontal, 3)
                        .background(selected ? colors.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.theme.\(option.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(colors.control, in: RoundedRectangle(cornerRadius: 9))
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
