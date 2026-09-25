import SwiftUI

enum SettingsLayout {
    static let pickerWidth: CGFloat = 150
}

struct SettingsColors {
    let scheme: ColorScheme

    var canvas: Color { scheme == .dark ? Color(white: 0.11) : .white }
    var sidebar: Color { scheme == .dark ? Color(white: 0.14) : Color(white: 0.975) }
    var selected: Color { scheme == .dark ? Color(white: 0.23) : .white }
    var control: Color { scheme == .dark ? Color(white: 0.18) : Color(white: 0.95) }
    var ink: Color { scheme == .dark ? Color(white: 0.94) : Color(white: 0.13) }
    var secondary: Color { scheme == .dark ? Color(white: 0.66) : Color(white: 0.48) }
    var border: Color { scheme == .dark ? Color(white: 0.31) : Color(white: 0.89) }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content
    var body: some View {
        let colors = SettingsColors(scheme: scheme)
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(colors.border, lineWidth: 1)
            }
    }
}

struct SettingsDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(SettingsColors(scheme: scheme).border)
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

/// A titled option with an explanation on the leading side and its control on the trailing side.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey?
    @ViewBuilder let control: Control

    init(_ title: LocalizedStringKey, caption: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                if let caption {
                    Text(caption).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}
