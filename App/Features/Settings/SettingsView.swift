import BrowserCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, performance, profiles, shortcuts
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .performance: "Performance"
        case .profiles: "Profiles"
        case .shortcuts: "Keyboard shortcuts"
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .appearance: "paintpalette"
        case .performance: "memorychip"
        case .profiles: "person.crop.circle"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsView: View {
    let browser: BrowserModel
    @State private var section: SettingsSection = .general
    @State private var profileEditor: ProfileEditorRequest?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear.frame(height: 46)
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 13, weight: section == item ? .medium : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(section == item ? Color.white : BrowserPalette(scheme: scheme).ink)
                            .background(section == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.\(item.rawValue)")
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 190)
            .background(BrowserPalette(scheme: scheme).sidebar)

            Rectangle().fill(BrowserPalette(scheme: scheme).line).frame(width: 1)
            VStack(alignment: .leading, spacing: 24) {
                Text(section.title).font(.system(size: 21, weight: .semibold))
                    .padding(.top, 30)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch section {
                        case .general: general
                        case .appearance: appearance
                        case .performance: PerformanceSettingsView(browser: browser)
                        case .profiles: profiles
                        case .shortcuts: shortcuts
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BrowserPalette(scheme: scheme).canvas)
        }
        .font(BrowserDesign.bodyFont)
        .foregroundStyle(BrowserPalette(scheme: scheme).ink)
        .frame(minWidth: 780, idealWidth: 800, minHeight: 540, idealHeight: 560)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfiguration(identifier: "aero.settings"))
        .sheet(item: $profileEditor) { request in
            ProfilesView(browser: browser, initialProfileID: request.profileID, startsCreating: request.profileID == nil)
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsRow("Language", caption: "Choose the language used by the browser.") {
                    Picker("Language", selection: Binding(get: { browser.preferences.language }, set: { browser.preferences.setLanguage($0) })) {
                        ForEach(BrowserLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsLayout.pickerWidth, alignment: .trailing)
                    .accessibilityIdentifier("settings.language")
                }
            }
            if browser.preferences.needsLanguageRestart {
                Label("Reopen the browser to apply the language change.", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("settings.languageRestart")
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose how the browser looks.").foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(BrowserAppearance.allCases, id: \.self) { option in
                    Button { browser.setAppearance(option) } label: {
                        VStack(spacing: 10) {
                            ThemePreview(appearance: option)
                                .frame(height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                                .overlay(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).strokeBorder(browser.session.appearance == option ? Color.accentColor : BrowserPalette(scheme: scheme).line, lineWidth: browser.session.appearance == option ? 2 : 1))
                            HStack(spacing: 5) {
                                Text(option.label)
                                if browser.session.appearance == option { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.theme.\(option.rawValue)")
                    .accessibilityAddTraits(browser.session.appearance == option ? .isSelected : [])
                }
            }
            SettingsCard { AppIconPicker(browser: browser) }
            SettingsCard {
                HStack(spacing: 14) {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                    Text("The accent color follows your active profile.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep website sign-ins and tabs separate.").foregroundStyle(.secondary)
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(browser.session.profiles.enumerated()), id: \.element.id) { index, profile in
                        if index > 0 { Divider().padding(.vertical, 12) }
                        HStack(spacing: 12) {
                            ProfileBadge(profile: profile, size: 32)
                            Text(verbatim: profile.name).fontWeight(.medium)
                            Spacer()
                            Button("Edit") { profileEditor = ProfileEditorRequest(profileID: profile.id) }
                        }
                    }
                }
            }
            Button("Add profile", systemImage: "plus") { profileEditor = ProfileEditorRequest(profileID: nil) }
                .accessibilityIdentifier("settings.addProfile")
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The essentials, always within reach.").foregroundStyle(.secondary)
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(BrowserCommand.allCases.filter { $0.shortcutLabel != nil }.enumerated()), id: \.element) { index, command in
                        if index > 0 { Divider().padding(.vertical, 10) }
                        HStack {
                            Text(verbatim: command.title)
                            Spacer()
                            if let shortcut = command.shortcutLabel { ShortcutLabel(text: shortcut) }
                        }
                    }
                    Divider().padding(.vertical, 10)
                    HStack {
                        Text("Switch recent tabs")
                        Spacer()
                        ShortcutLabel(text: "⌃ ⇥")
                    }
                }
            }
        }
    }
}

private struct ProfileEditorRequest: Identifiable {
    let id = UUID()
    let profileID: UUID?
}

private struct ThemePreview: View {
    let appearance: BrowserAppearance
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = appearance == .dark || (appearance == .system && scheme == .dark)
        let palette = BrowserPalette(scheme: dark ? .dark : .light)
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) { ForEach(0..<3) { _ in Circle().fill(palette.secondary.opacity(0.5)).frame(width: 3, height: 3) } }
                RoundedRectangle(cornerRadius: 2).fill(palette.secondary.opacity(0.15)).frame(height: 6)
                RoundedRectangle(cornerRadius: 2).fill(palette.secondary.opacity(0.10)).frame(height: 6)
                Spacer(minLength: 0)
            }.frame(width: 25)
            RoundedRectangle(cornerRadius: 5).fill(palette.canvas)
                .overlay { RoundedRectangle(cornerRadius: 3).fill(palette.raised).frame(width: 35, height: 10) }
        }
        .padding(8).background(palette.sidebar)
        .accessibilityHidden(true)
    }
}
