import SwiftUI

enum SettingsLayout {
    static let pickerWidth: CGFloat = 150
    /// Between cards, and between a page's title and its first card.
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 12
}

struct SettingsCard<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(SettingsLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.card)
    }
}

/// Separates the rows of a card.
struct SettingsDivider: View {
    var body: some View {
        Hairline().padding(.vertical, SettingsLayout.rowSpacing)
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
                Text(title).font(BrowserDesign.Typography.label)
                if let caption {
                    Text(caption).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}
