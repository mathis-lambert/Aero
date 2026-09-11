import SwiftUI

enum SettingsLayout {
    static let pickerWidth: CGFloat = 160
}

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(BrowserPalette(scheme: scheme).raised, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
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
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
    }
}
